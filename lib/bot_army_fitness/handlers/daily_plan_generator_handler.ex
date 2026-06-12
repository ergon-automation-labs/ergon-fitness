defmodule BotArmyFitness.Handlers.DailyPlanGeneratorHandler do
  @moduledoc "Generates daily fitness plans via LLM using workout history and comfort data."

  require Logger
  alias BotArmyFitness.{CardioSessionStore, DailyPlanStore, PersonalExerciseStore}
  alias BotArmyRuntime.NATS.Publisher

  def handle_generate(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)

    try do
      workout_type = determine_workout_type(tenant_id)
      strength_context = load_strength_context(tenant_id)
      cardio_context = load_cardio_context(tenant_id)

      prompt = build_prompt(workout_type, strength_context, cardio_context)

      llm_request = %{
        "text" => prompt,
        "type" => "daily_plan",
        "source_domain" => "fitness",
        "model" => "auto",
        "tenant_id" => tenant_id
      }

      case Publisher.publish("llm.response.parse", llm_request) do
        {:ok, _} ->
          Logger.info(
            "[DailyPlanGenerator] Published plan generation request for #{workout_type}"
          )

        {:error, reason} ->
          Logger.warning("[DailyPlanGenerator] Failed to publish LLM request: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.error("[DailyPlanGenerator] Error in handle_generate: #{inspect(e)}")
    end

    :ok
  end

  def handle_llm_response(payload) do
    case get_in(payload, ["structured_data"]) do
      nil ->
        Logger.warning("[DailyPlanGenerator] No structured_data in LLM response")
        :ok

      plan_data ->
        tenant_id = payload["tenant_id"]
        type = plan_data["type"] || "full_body"
        estimated_minutes = plan_data["estimated_minutes"] || 45
        motivational_quote = plan_data["motivational_quote"] || ""
        video_url = plan_data["video_url"]
        exercises = plan_data["exercises"] || []
        notes = plan_data["notes"] || ""

        plan = %{
          "type" => type,
          "estimated_minutes" => estimated_minutes,
          "motivational_quote" => motivational_quote,
          "video_url" => video_url,
          "exercises" => exercises,
          "notes" => notes,
          "plan_json" => plan_data
        }

        case DailyPlanStore.create_plan(tenant_id, plan) do
          {:ok, _} ->
            Logger.info("[DailyPlanGenerator] Stored daily plan: #{type}")
            write_plan_to_para(tenant_id, plan_data)
            create_gtd_task(tenant_id, plan_data)

          {:error, reason} ->
            Logger.warning("[DailyPlanGenerator] Failed to store plan: #{inspect(reason)}")
        end

        :ok
    end
  end

  # Private

  defp determine_workout_type(tenant_id) do
    case DailyPlanStore.get_recent_plans(tenant_id, 3) do
      [] ->
        "full_body"

      [recent | _] ->
        case recent.type do
          "strength" -> "cardio"
          "cardio" -> "strength"
          "rest" -> "full_body"
          "yoga" -> "strength"
          _ -> "full_body"
        end
    end
  end

  defp load_strength_context(tenant_id) do
    exercises = PersonalExerciseStore.list_all(tenant_id)

    Enum.map(exercises, fn ex ->
      %{
        "name" => ex.name,
        "comfort" => ex.comfort_level || 5.0,
        "times_performed" => ex.times_performed || 0,
        "equipment" => ex.equipment_type,
        "notes" => ex.notes
      }
    end)
  end

  defp load_cardio_context(tenant_id) do
    # Group recent cardio sessions by activity type
    case CardioSessionStore.list_recent(tenant_id, 14) do
      {:ok, sessions} ->
        sessions
        |> Enum.group_by(& &1["activity_type"])
        |> Enum.map(fn {activity, group} ->
          avg_comfort = CardioSessionStore.get_activity_comfort(tenant_id, activity)
          avg_pace = calculate_avg_pace(group)
          recent = List.first(group)

          %{
            "activity" => activity,
            "avg_comfort" => avg_comfort,
            "avg_pace" => avg_pace,
            "streak_days" => recent["streak_days"] || 0
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp calculate_avg_pace(sessions) do
    paces = Enum.map(sessions, & &1["pace_per_mile"])
    avg = Enum.sum(paces) / max(length(paces), 1)
    Float.round(avg, 2)
  end

  defp build_prompt(workout_type, strength_context, cardio_context) do
    strength_list =
      Enum.map_join(strength_context, "\n", fn ex ->
        "- #{ex["name"]}: comfort #{ex["comfort"]}/10 (done #{ex["times_performed"]}×), equipment: #{ex["equipment"]}"
      end)

    cardio_list =
      Enum.map_join(cardio_context, "\n", fn c ->
        "- #{c["activity"]}: avg comfort #{c["avg_comfort"]}/10, streak #{c["streak_days"]} days, avg pace #{c["avg_pace"]} min/mi"
      end)

    """
    You are a personal fitness coach. Generate a daily workout plan.

    Today's focus: #{String.upcase(workout_type)}

    **Strength exercises by comfort (1=hard, 10=easy):**
    #{strength_list}

    **Recent cardio activity:**
    #{cardio_list}

    Based on comfort levels and recent activity, suggest a progressive workout that:
    1. Includes exercises with medium comfort (4-7) for main gains
    2. Suggests progression for high-comfort exercises (7+)
    3. Keeps challenging exercises (comfort < 4) at current volume or lighter
    4. Includes warm-up and optional cardio based on type

    Respond with ONLY valid JSON (no markdown, no explanation):
    {
      "type": "upper_strength|lower_strength|cardio|full_body|yoga|rest",
      "estimated_minutes": <integer>,
      "motivational_quote": "<string>",
      "exercises": [
        {
          "name": "<exercise name>",
          "sets": <integer>,
          "reps": <integer>,
          "rest_seconds": <integer>,
          "notes": "<progression notes or cues>"
        }
      ],
      "notes": "<summary or coaching notes>"
    }
    """
  end

  defp write_plan_to_para(_tenant_id, plan_data) do
    date_str = Date.to_string(Date.utc_today())
    content = format_plan_markdown(plan_data, date_str)

    payload = %{
      "schema_version" => "1.0",
      "relative_path" => "resources/fitness/plans/#{date_str}.md",
      "content" => content,
      "mode" => "write"
    }

    case Publisher.publish("para.fs.write", payload) do
      {:ok, _} ->
        Logger.info("[DailyPlanGenerator] PARA plan exported: #{date_str}")

      {:error, reason} ->
        Logger.warning("[DailyPlanGenerator] PARA export failed: #{inspect(reason)}")
    end
  end

  defp format_plan_markdown(plan_data, date_str) do
    type = plan_data["type"] || "workout"
    est_minutes = plan_data["estimated_minutes"] || 45
    quote_ = plan_data["motivational_quote"] || ""
    notes = plan_data["notes"] || ""
    exercises = plan_data["exercises"] || []

    exercise_rows =
      Enum.map_join(exercises, "\n", fn ex ->
        sets = ex["sets"] || "?"
        reps = ex["reps"] || "?"
        rest = ex["rest_seconds"] || "?"
        ex_notes = ex["notes"] || ""
        "| #{ex["name"]} | #{sets} | #{reps} | #{rest}s | #{ex_notes} |"
      end)

    """
    # Morning Workout — #{date_str}

    **Type:** #{type}
    **Estimated duration:** #{est_minutes} min

    > #{quote_}

    ## Exercises

    | Exercise | Sets | Reps | Rest | Notes |
    |----------|------|------|------|-------|
    #{exercise_rows}

    ## Notes

    #{notes}
    """
  end

  defp create_gtd_task(tenant_id, plan_data) do
    date_str = Date.to_string(Date.utc_today())
    type = plan_data["type"] || "workout"
    minutes = plan_data["estimated_minutes"] || 45

    envelope = %{
      "event" => "gtd.task.create",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "fitness.scheduler",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{
        "title" => "Morning workout — #{date_str} (#{type}, #{minutes}min)",
        "context" => "next",
        "priority" => "normal",
        "labels" => ["fitness"]
      }
    }

    case BotArmyFitness.GTDClient.request("gtd.task.create", envelope, timeout_ms: 5_000) do
      {:ok, %{"data" => %{"task_id" => task_id}}} ->
        Logger.info("[DailyPlanGenerator] GTD task created: #{task_id}")

      {:error, reason} ->
        Logger.warning("[DailyPlanGenerator] GTD task creation failed: #{inspect(reason)}")
    end
  end
end

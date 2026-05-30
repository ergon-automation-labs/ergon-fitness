defmodule BotArmyFitness.Handlers.WorkoutPlanHandler do
  @moduledoc """
  Handles workout plan generation requests and LLM responses.

  Triggers LLM for plan generation based on fitness goals,
  and processes the completed plan responses.
  """

  require Logger

  @doc """
  Handle workout plan request.

  Retrieves goal details and initiates LLM plan generation.
  """
  def handle_plan_request(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}
    goal_id = payload["goal_id"]

    case goal_id && goal_store().get(tenant_id, goal_id) do
      nil ->
        Logger.warning("fitness.workout.plan.request: goal not found or missing goal_id")
        :ok

      goal ->
        {:ok, workouts} = workout_store().list(tenant_id)
        plan_request_id = UUID.uuid4()

        llm_request = %{
          "text" => build_plan_prompt(goal, length(workouts)),
          "type" => "workout_plan",
          "source_domain" => "fitness",
          "goal_id" => goal_id,
          "plan_request_id" => plan_request_id,
          "model" => "auto",
          "tenant_id" => tenant_id,
          "user_id" => user_id
        }

        BotArmyRuntime.NATS.Publisher.publish("llm.response.parse", llm_request)
        Logger.info("LLM plan request sent: plan_request_id=#{plan_request_id}")
        :ok
    end
  end

  @doc """
  Handle LLM response for workout plan.

  Processes completed plan and publishes fitness.workout.plan.ready event.
  """
  def handle_llm_response(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}

    with "fitness" <- payload["source_domain"],
         "workout_plan" <- payload["type"] do
      structured = payload["structured_data"] || %{}

      event_data = %{
        "event" => "fitness.workout.plan.ready",
        "event_id" => UUID.uuid4(),
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "source" => "bot_army_fitness",
        "source_node" => node() |> Atom.to_string(),
        "triggered_by" => "fitness.llm",
        "schema_version" => "1.0",
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "payload" => %{
          "goal_id" => payload["goal_id"],
          "plan_request_id" => payload["plan_request_id"],
          "plan" => structured["plan"],
          "weekly_sessions" => structured["weekly_sessions"],
          "notes" => structured["notes"]
        }
      }

      BotArmyFitness.NATS.Publisher.publish(event_data)
    else
      # not for us
      _ -> :ok
    end
  end

  # Private functions

  defp build_plan_prompt(goal, recent_workout_count) do
    days_remaining =
      case Date.from_iso8601(to_string(goal["target_date"])) do
        {:ok, target_date} -> Date.diff(target_date, Date.utc_today())
        _ -> nil
      end

    """
    You are a certified personal trainer. Generate a structured weekly workout plan.

    Goal: #{goal["title"]}
    Goal type: #{goal["goal_type"] || "general fitness"}
    Target: #{goal["target_value"] || "not specified"}
    Target date: #{goal["target_date"]} (#{days_remaining} days remaining)
    Recent workouts (last 30 days): #{recent_workout_count} sessions

    Return JSON with keys:
    - "plan": string — 3-5 sentence description of the weekly structure
    - "weekly_sessions": integer — recommended sessions per week
    - "notes": string — progressions and caveats to watch for
    """
  end

  defp goal_store,
    do: Application.get_env(:bot_army_fitness, :goal_store, BotArmyFitness.GoalStore)

  defp workout_store,
    do: Application.get_env(:bot_army_fitness, :workout_store, BotArmyFitness.WorkoutStore)
end

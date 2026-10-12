defmodule BotArmyFitness.Handlers.TodayPlanHandler do
  @moduledoc """
  Answers `fitness.workout.today` — today's rotation plan.

  ## Two crash paths, both fixed

  This handler used to kill the whole consumer process
  (`BotArmyFitness.NATS.Consumer`), taking every fitness NATS subscription down
  with it, on **both** of its branches:

    * the cold branch built the description with `"\#{workout_type.downcase()}"`.
      `workout_type` is a binary from `@workout_types`, and `binary.downcase/0`
      does not exist, so `:erlang.apply("Yoga", :downcase, [])` raised
      `ArgumentError`. Measured live: 36 `:downcase` crashes in
      `/var/log/bot_army/fitness_bot.err`, every one of them terminating the
      consumer;
    * the warm branch handed the `%DailyPlan{}` **struct** to `format_response/1`,
      which read it with `plan["description"]`. Ecto schemas do not implement
      `Access`, so that raised `UndefinedFunctionError` as well.

  It also called `DailyPlanStore.save_today/1`, which does not exist — the
  `rescue _ -> :ok` around the call swallowed the `UndefinedFunctionError`, so the
  rotation plan was never cached and every request took the crashy cold branch.

  The rotation plan is a pure function of `(user_id, date)`: the seed is the sum
  of the user id's codepoints and the rotation is by day of year. It is therefore
  rebuilt per request and there is nothing to cache. `build_plan/3` is public and
  pure so the plan is testable without a database, mirroring the reason
  `WorkoutHandler.list_response/1` was split out of `handle_list/2`.
  """

  require Logger

  alias BotArmyFitness.DailyPlanStore
  alias BotArmyFitness.Schemas.DailyPlan
  alias BotArmyFitness.WorkoutTypes

  @doc """
  Build the reply for `fitness.workout.today`.

  Returns a plain map (the consumer JSON-encodes it) and never raises: a stored
  plan is formatted from the struct's columns, a missing one is generated from
  the rotation.
  """
  def handle_request(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyLibraryCore.Tenant.extract_context(message)

    case DailyPlanStore.get_today(tenant_id) do
      {:ok, plan} ->
        Logger.info("[TodayPlanHandler] Returning stored plan for #{tenant_id}")
        format_stored_plan(plan)

      {:error, :not_found} ->
        Logger.info("[TodayPlanHandler] Generating plan for #{tenant_id}")

        tenant_id
        |> build_plan(user_id, Date.utc_today())
        |> format_response()
    end
  end

  @doc """
  Build today's rotation plan for a user. Pure — `date` is injected, nothing is
  written, and no store is read.

  `workout_type` is a canonical value from `BotArmyFitness.WorkoutTypes`, so a
  stored plan and a logged workout are comparable; the human prose uses the
  label.
  """
  def build_plan(tenant_id, user_id, %Date{} = date) do
    day_of_year = Date.day_of_year(date)
    workout_type = Enum.at(WorkoutTypes.types(), seed_for(user_id))
    duration = 30 + Integer.mod(day_of_year, 31)
    intensity = Enum.at(WorkoutTypes.intensities(), Integer.mod(day_of_year, 3))
    calories = duration * calorie_multiplier(intensity)

    %{
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "date" => Date.to_string(date),
      "title" => "#{WorkoutTypes.label(workout_type)} — #{duration} mins",
      "workout_type" => workout_type,
      "duration_minutes" => duration,
      "intensity" => intensity,
      "estimated_calories" => calories,
      "description" => description(workout_type, duration, intensity, calories),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Format a plan map into the reply the consumer encodes.

  A field the plan does not carry stays `nil` rather than being invented, so the
  reply says what is actually known.
  """
  def format_response(plan) when is_map(plan) do
    %{
      "ok" => true,
      "data" => %{
        "plan" => plan["description"],
        "title" => plan["title"],
        "workout_type" => plan["workout_type"],
        "duration_minutes" => plan["duration_minutes"],
        "intensity" => plan["intensity"],
        "estimated_calories" => plan["estimated_calories"]
      }
    }
  end

  @doc """
  Format a `%DailyPlan{}` read back from the store.

  `plan_json` holds the map the plan was generated from (the LLM generator stores
  its own shape there); when it carries a description it is used as-is. Otherwise
  the plan is rendered from the struct's columns. Either way the caller gets the
  single shape `format_response/1` produces.
  """
  def format_stored_plan(%DailyPlan{} = plan) do
    plan |> stored_plan_map() |> format_response()
  end

  # Private functions

  defp stored_plan_map(%DailyPlan{plan_json: %{"description" => _} = stored}), do: stored

  defp stored_plan_map(%DailyPlan{} = plan) do
    %{
      "title" => plan.type,
      "workout_type" => plan.type,
      "duration_minutes" => plan.estimated_minutes,
      "description" => plan.motivational_quote || plan.notes
    }
  end

  defp seed_for(user_id) do
    user_id
    |> to_string()
    |> String.to_charlist()
    |> Enum.sum()
    |> Integer.mod(length(WorkoutTypes.types()))
  end

  defp calorie_multiplier("intense"), do: 12
  defp calorie_multiplier("moderate"), do: 10
  defp calorie_multiplier(_), do: 7

  defp description(workout_type, duration, intensity, calories) do
    "#{WorkoutTypes.label(workout_type)} for #{duration} minutes at #{intensity} intensity. " <>
      "Est. #{calories} calories burned."
  end
end

defmodule BotArmyFitness.Handlers.TodayPlanHandler do
  require Logger
  alias BotArmyFitness.DailyPlanStore

  def handle_request(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)

    case DailyPlanStore.get_today(tenant_id) do
      {:ok, plan} ->
        Logger.info("[TodayPlanHandler] Returning cached plan for #{tenant_id}")
        format_response(plan)

      {:error, :not_found} ->
        Logger.info("[TodayPlanHandler] Generating plan for #{tenant_id}")
        plan = generate_plan(tenant_id, user_id)
        format_response(plan)
    end
  end

  defp generate_plan(tenant_id, user_id) do
    # Simple rotation-based plan generation
    workout_types = ["Running", "Strength Training", "Yoga", "Cycling", "HIIT", "Swimming"]
    intensities = ["light", "moderate", "intense"]

    # Use user_id hash to seed consistent randomness per day
    day_of_year = Date.utc_today() |> Date.day_of_year()
    seed = String.to_charlist(user_id) |> Enum.sum() |> Integer.mod(6)
    intensity_seed = Integer.mod(day_of_year, 3)

    workout_type = Enum.at(workout_types, seed, "Running")
    duration = 30 + Integer.mod(day_of_year, 31)
    intensity = Enum.at(intensities, intensity_seed, "moderate")

    calorie_multiplier =
      cond do
        intensity == "intense" -> 12
        intensity == "moderate" -> 10
        true -> 7
      end

    calories = duration * calorie_multiplier

    plan = %{
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "date" => Date.utc_today() |> Date.to_string(),
      "title" => "#{workout_type} — #{duration} mins",
      "workout_type" => String.downcase(workout_type),
      "duration_minutes" => duration,
      "intensity" => intensity,
      "estimated_calories" => calories,
      "description" =>
        "#{workout_type.downcase()} for #{duration} minutes at #{intensity} intensity. Est. #{calories} calories burned.",
      "generated_at" => DateTime.utc_now() |> DateTime.to_string()
    }

    # Cache it for the rest of the day
    try do
      DailyPlanStore.save_today(plan)
    rescue
      _ -> :ok
    end

    plan
  end

  defp format_response(plan) do
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
end

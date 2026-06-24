defmodule BotArmyFitness.Scheduler do
  @moduledoc """
  Fitness reminders via shared reminder scheduler library.

  Provides check function for BotArmyReminderScheduler to determine
  when to remind about workouts based on time since last workout.

  Uses urgency escalation:
  - "due": 1+ days since last workout
  - "overdue": 3+ days since last workout
  - "urgent": 7+ days since last workout
  """

  require Logger

  @doc """
  Check for workouts that need reminding.

  Called by BotArmyReminderScheduler on a periodic basis (default: hourly).
  Returns list of {goal_id, days_since_workout} tuples for goals that haven't been exercised.
  """
  def check_workouts_needed() do
    try do
      BotArmyFitness.FitnessStore.get_all_fitness_goals()
      |> Enum.map(fn goal ->
        last_workout = BotArmyFitness.FitnessStore.get_last_workout_date(goal.id)
        days_since = calculate_days_since(last_workout)

        if days_since > 0 do
          {goal.id, days_since}
        end
      end)
      |> Enum.filter(&(&1 != nil))
    rescue
      e ->
        Logger.error("[FitnessScheduler] Error checking workouts: #{inspect(e)}")
        []
    end
  end

  defp calculate_days_since(last_workout_date) do
    case last_workout_date do
      nil ->
        # Never worked out, consider it urgent
        999

      last_date ->
        last_datetime =
          if is_struct(last_date, DateTime) do
            last_date
          else
            DateTime.new!(last_date, ~T[00:00:00])
          end

        DateTime.utc_now()
        |> DateTime.diff(last_datetime, :second)
        # seconds per day
        |> div(86400)
    end
  end
end

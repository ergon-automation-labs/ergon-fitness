defmodule BotArmyFitness.Scheduler do
  @moduledoc """
  Fitness reminders via shared reminder scheduler library.

  Provides check function for BotArmyLibraryRuntime.Reminders to determine
  when to remind about workouts based on time since last workout.

  Uses urgency escalation:
  - "due": 1+ days since last workout
  - "overdue": 3+ days since last workout
  - "urgent": 7+ days since last workout
  """

  require Logger

  alias BotArmyFitness.{GoalStore, WorkoutStore}
  alias BotArmyLibraryCore.Tenant

  # "Never worked out" sentinel — deliberately past the "urgent" tier (7+) so a
  # goal with no workouts on record escalates immediately.
  @never_worked_out 999

  @doc """
  Check for workouts that need reminding.

  Called by BotArmyLibraryRuntime.Reminders on a periodic basis (default: hourly).
  Returns list of {goal_id, days_since_workout} tuples for goals that haven't been exercised.

  Workouts carry no `goal_id` (see the workouts table), so "days since last
  workout" is one tenant-wide signal shared by every active goal rather than a
  per-goal one.

  A store read that fails skips the cycle instead of reporting "no workouts",
  which would escalate straight to the urgent tier.
  """
  def check_workouts_needed do
    try do
      tenant_id = Tenant.default_tenant_id()

      case workout_store().list(tenant_id) do
        {:ok, workouts} when is_list(workouts) ->
          build_reminders(goal_store().list(tenant_id), latest_workout_date(workouts))

        other ->
          Logger.warning(
            "[FitnessScheduler] Could not read workouts, skipping this cycle: #{inspect(other)}"
          )

          []
      end
    rescue
      e ->
        Logger.error("[FitnessScheduler] Error checking workouts: #{inspect(e)}")
        []
    end
  end

  defp build_reminders(goals, last_workout_date) do
    goals
    |> Enum.filter(&active?/1)
    |> Enum.map(fn goal -> {goal["id"], calculate_days_since(last_workout_date)} end)
    |> Enum.filter(fn {_goal_id, days_since} -> days_since > 0 end)
  end

  # Injectable store accessors, same seam the handlers use, so the reminder cycle
  # is testable without a database.
  defp goal_store, do: Application.get_env(:bot_army_fitness, :goal_store, GoalStore)
  defp workout_store, do: Application.get_env(:bot_army_fitness, :workout_store, WorkoutStore)

  @doc false
  # Normalise at the boundary: workout dates may arrive as Date structs (loaded
  # from the DB) or ISO 8601 strings (inserted from a request payload).
  #
  # Sorted by gregorian days, not by the struct: Enum.max/1 on Date structs
  # compares maps structurally (calendar, then day, then month, then year), so it
  # would happily pick the 31st of the month over the 1st.
  def latest_workout_date(workouts) do
    workouts
    |> Enum.map(&workout_date/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&Date.to_gregorian_days/1, :desc)
    |> List.first()
  end

  defp workout_date(%{"date" => %Date{} = date}), do: date

  defp workout_date(%{"date" => date}) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, _} -> nil
    end
  end

  defp workout_date(_other), do: nil

  # A completed or abandoned goal must not nag.
  defp active?(goal), do: Map.get(goal, "status", "active") in [nil, "active"]

  defp calculate_days_since(nil), do: @never_worked_out
  defp calculate_days_since(%Date{} = date), do: Date.diff(Date.utc_today(), date)
  defp calculate_days_since(_other), do: @never_worked_out
end

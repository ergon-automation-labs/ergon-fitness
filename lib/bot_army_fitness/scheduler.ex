defmodule BotArmyFitness.Scheduler do
  @moduledoc """
  Fitness reminders via shared reminder scheduler library.

  Provides check function for BotArmyLibraryRuntime.Reminders to determine
  when to remind about workouts based on time since last workout.

  Uses urgency escalation:
  - "due": 1+ days since last workout
  - "overdue": 3+ days since last workout
  - "urgent": 7+ days since last workout

  This module owns the fleet's only "days since the last workout" read: the
  reminder cycle (`check_workouts_needed/0`) and, since the social check-in was
  wired up, `days_since_last_workout/0` — the same read exposed as a plain fact
  for callers that need the number rather than a reminder. The pulse publisher
  is such a caller; it must not recompute the fact from its own counters, which
  reset on every restart and would report "worked out today".
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

  @doc """
  Days since the most recent workout on record, read fresh from the store.

    * `{:ok, days}` — the newest workout's date was readable. `days` is 0 when a
      workout was logged today, and may be negative for a future-dated row.
    * `{:ok, #{@never_worked_out}}` — nothing has ever been recorded. That sentinel is
      deliberately past the urgent tier, so "never" escalates instead of being read
      as "today".
    * `{:error, reason}` — the store could not be read. Callers **must not** treat
      this as "no workouts": a failed read is not a health fact, and the invitation
      this feeds must not be sent because a database hiccup looked like a streak of
      misses.

  Days are counted against `Date.utc_today()`, the day convention this bot already
  uses for workout dates (see `BotArmyFitness.WorkoutStore.workout_date/1`); it is
  not the household's local midnight.
  """
  def days_since_last_workout do
    try do
      case workout_store().list(Tenant.default_tenant_id()) do
        {:ok, workouts} when is_list(workouts) ->
          {:ok, days_since(latest_workout_date(workouts))}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_store_reply, other}}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp build_reminders(goals, last_workout_date) do
    goals
    |> Enum.filter(&active?/1)
    |> Enum.map(fn goal -> {goal["id"], days_since(last_workout_date)} end)
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

  @doc false
  # The pure half of "days since last workout": a Date becomes a count of days
  # against today, and anything unreadable (nil, a malformed row) collapses to the
  # never-worked-out sentinel rather than being reported as "today".
  def days_since(nil), do: @never_worked_out
  def days_since(%Date{} = date), do: Date.diff(Date.utc_today(), date)
  def days_since(_other), do: @never_worked_out
end

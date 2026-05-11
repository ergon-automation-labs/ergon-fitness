defmodule BotArmyFitness.GoalScheduler do
  @moduledoc """
  GenServer for managing fitness goal progress tracking.

  Periodically checks goals nearing their targets and publishes reminder events.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Fitness GoalScheduler started")
    schedule_next_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_goals, state) do
    check_goals_nearing_deadline()
    schedule_next_check()
    {:noreply, state}
  end

  defp schedule_next_check do
    # Schedule for next midnight
    ms_until_midnight = ms_until_next_midnight()
    Process.send_after(self(), :check_goals, ms_until_midnight)
  end

  defp ms_until_next_midnight do
    now = DateTime.utc_now()
    # Calculate tomorrow at 00:00:00 UTC
    tomorrow_at_midnight =
      now
      |> DateTime.add(1, :day)
      |> then(fn dt -> DateTime.new!(DateTime.to_date(dt), ~T[00:00:00], "Etc/UTC") end)

    DateTime.diff(tomorrow_at_midnight, now, :millisecond)
  end

  defp check_goals_nearing_deadline do
    goals = BotArmyFitness.GoalStore.list(BotArmyCore.Tenant.default_tenant_id())

    Enum.each(goals, fn goal ->
      if should_remind_goal(goal) do
        publish_reminder(goal)
      end
    end)
  end

  defp should_remind_goal(goal) do
    case goal["target_date"] do
      nil ->
        false

      date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, target_date} ->
            days_remaining = Date.diff(target_date, Date.utc_today())
            days_remaining > 0 && days_remaining <= 7

          _ ->
            false
        end
    end
  end

  defp publish_reminder(goal) do
    event_data = %{
      "event" => "fitness.goal.reminder",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => get_node_name(),
      "triggered_by" => "fitness.scheduler",
      "schema_version" => "1.0",
      "payload" => %{
        "goal_id" => goal["id"],
        "title" => goal["title"],
        "target_date" => goal["target_date"],
        "days_remaining" => days_until_target(goal["target_date"])
      }
    }

    BotArmyFitness.NATS.Publisher.publish(event_data)
  end

  defp days_until_target(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, target_date} -> Date.diff(target_date, Date.utc_today())
      _ -> nil
    end
  end

  defp days_until_target(_), do: nil

  defp get_node_name do
    node() |> Atom.to_string()
  end
end

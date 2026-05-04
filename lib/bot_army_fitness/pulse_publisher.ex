defmodule BotArmyFitness.PulsePublisher do
  @moduledoc """
  Publishes health pulses for the Fitness bot.

  Tracks fitness metrics:
  - Workouts logged
  - Streak status
  - Active goals
  """

  use GenServer
  require Logger

  @health_interval_ms 30 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_publish()
    Process.send_after(self(), :publish_health, 2_000)
    {:ok, %{workouts: 0, streak_days: 0, active_goals: 0}}
  end

  def record_workout do
    GenServer.cast(__MODULE__, :workout)
  end

  def record_streak_update(days) do
    GenServer.cast(__MODULE__, {:streak, days})
  end

  def record_goal_active do
    GenServer.cast(__MODULE__, :goal_active)
  end

  @impl true
  def handle_cast(:workout, state) do
    {:noreply, Map.update(state, :workouts, 1, &(&1 + 1))}
  end

  @impl true
  def handle_cast({:streak, days}, state) do
    {:noreply, Map.put(state, :streak_days, days)}
  end

  @impl true
  def handle_cast(:goal_active, state) do
    {:noreply, Map.update(state, :active_goals, 1, &(&1 + 1))}
  end

  @impl true
  def handle_info(:publish, state) do
    pulse = publish_pulse(state)
    BotArmyFitness.IntentEvaluator.record_observations(pulse)
    schedule_publish()
    {:noreply, %{workouts: 0, streak_days: state.streak_days, active_goals: 0}}
  end

  @impl true
  def handle_info(:publish_health, state) do
    publish_system_health(state)
    Process.send_after(self(), :publish_health, @health_interval_ms)
    {:noreply, state}
  end

  defp schedule_publish do
    Process.send_after(self(), :publish, 5 * 60 * 1000)
  end

  defp publish_system_health(metrics) do
    health_signal =
      if metrics.workouts > 0 or metrics.streak_days > 0, do: "nominal", else: "degraded"

    BotArmyRuntime.SynapseHealth.publish(
      source: "bot_army_fitness",
      service: "fitness",
      health_signal: health_signal
    )
  end

  defp publish_pulse(metrics) do
    try do
      health_signal =
        if metrics.workouts > 0 or metrics.streak_days > 0, do: "nominal", else: "degraded"

      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "service" => "fitness",
        "health_signal" => health_signal,
        "metrics" => %{
          "workouts" => metrics.workouts,
          "streak_days" => metrics.streak_days,
          "active_goals" => metrics.active_goals
        },
        "observations" => %{
          "idle_minutes" => if(metrics.workouts == 0, do: 60, else: 0),
          "streak_at_risk" =>
            if(metrics.streak_days > 0 and metrics.workouts == 0, do: 1, else: 0)
        }
      }

      subject = "bot.fitness.pulse"

      case BotArmyRuntime.NATS.Publisher.publish(subject, payload) do
        {:ok, _} -> Logger.info("[PulsePublisher] Published fitness pulse")
        {:error, reason} -> Logger.warning("[PulsePublisher] Publish failed: #{inspect(reason)}")
      end

      payload
    rescue
      e ->
        Logger.error("[PulsePublisher] Error: #{inspect(e)}")
        %{}
    end
  end
end

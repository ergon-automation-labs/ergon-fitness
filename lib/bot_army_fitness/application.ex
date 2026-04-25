defmodule BotArmyFitness.Application do
  @moduledoc """
  BotArmyFitness application supervisor.

  Manages fitness bot services:
  - NATS message consumer
  - Workout tracker
  - Goal progress monitor
  """

  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_workout_store()
      |> maybe_add_goal_store()
      |> maybe_add_goal_scheduler()
      |> maybe_add_pulse_publisher()
      |> maybe_add_consumer()

    opts = [strategy: :one_for_one, name: BotArmyFitness.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyFitness.Repo | children]
  end

  defp maybe_add_workout_store(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.WorkoutStore, []} | children]
  end

  defp maybe_add_goal_store(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.GoalStore, []} | children]
  end

  defp maybe_add_goal_scheduler(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.GoalScheduler, []} | children]
  end

  defp maybe_add_pulse_publisher(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.PulsePublisher, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.NATS.Consumer, []} | children]
  end
end

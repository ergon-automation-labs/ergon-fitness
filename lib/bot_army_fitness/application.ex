defmodule BotArmyFitness.Application do
  @moduledoc """
  BotArmyFitness application supervisor.

  Manages fitness bot services:
  - NATS message consumer
  - Workout tracker
  - Goal progress monitor
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []
    |> maybe_add_repo()
    |> maybe_add_workout_store()
    |> maybe_add_consumer()

    opts = [strategy: :one_for_one, name: BotArmyFitness.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if Mix.env() == :test, do: children, else: [BotArmyFitness.Repo | children]
  end

  defp maybe_add_workout_store(children) do
    if Application.get_env(:bot_army_fitness, :workout_store) == BotArmyFitness.WorkoutStore do
      [{BotArmyFitness.WorkoutStore, []} | children]
    else
      children
    end
  end

  defp maybe_add_consumer(children) do
    if Mix.env() == :test, do: children, else: [{BotArmyFitness.NATS.Consumer, []} | children]
  end
end

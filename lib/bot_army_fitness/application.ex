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
    children = [
      # Database connection
      BotArmyFitness.Repo,

      # Workout storage (in-memory + Ecto persistence)
      {BotArmyFitness.WorkoutStore, []},

      # NATS connection and consumer
      {BotArmyFitness.NATS.Consumer, []}
    ]

    opts = [strategy: :one_for_one, name: BotArmyFitness.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

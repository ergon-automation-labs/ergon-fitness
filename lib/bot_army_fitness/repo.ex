defmodule BotArmyFitness.Repo do
  @moduledoc """
  Ecto Repository for the Fitness bot.

  Provides database access for workouts and goals with PostgreSQL backend.
  """

  use Ecto.Repo,
    otp_app: :bot_army_fitness,
    adapter: Ecto.Adapters.Postgres
end

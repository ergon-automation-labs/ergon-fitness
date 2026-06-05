defmodule FitnessBot.Release do
  @moduledoc """
  Release tasks for the Fitness bot.

  Migrations are run via the shared BotArmyRuntime.Ecto.MigrationRunner:

      /path/to/fitness_bot/bin/fitness_bot eval 'FitnessBot.Release.migrate()'

  Called from Salt during bot deployment, before the bot starts.
  """

  alias BotArmyRuntime.Ecto.MigrationRunner

  @app :bot_army_fitness

  def migrate do
    MigrationRunner.run(
      repo_module: BotArmyFitness.Repo,
      app_module: @app
    )
  end
end

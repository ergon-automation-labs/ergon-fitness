import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

if config_env() != :test do
  alias BotArmyLibraryRuntime.Ecto.RuntimeDbConfig

  db_config =
    RuntimeDbConfig.resolve("BOT_ARMY_FITNESS", database: "ergon_fitness_dev", port: 30003)

  config(
    :bot_army_fitness,
    BotArmyFitness.Repo,
    Keyword.merge(db_config, [
      pool_size: RuntimeDbConfig.pool_size("BOT_ARMY_FITNESS", 10),
      ssl: false
    ])
  )
end

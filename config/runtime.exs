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
    Keyword.merge(db_config,
      pool_size: RuntimeDbConfig.pool_size("BOT_ARMY_FITNESS", 10),
      ssl: false
    )
  )
end

# NATS connection.
#
# BotArmyLibraryRuntime.NATS.Connection resolves servers from app config only
# (opts -> :bot_army_library_runtime, :nats, servers -> fail-safe default of the
# dev broker, port 4223). It does NOT read NATS_HOST/NATS_PORT itself, so a bot
# that omits this block silently lands on the dev broker no matter what the
# plist says. Every other bot sets it here from the environment; deploy plists
# opt a bot into production with NATS_PORT=4222 (fail-safe policy: unset env
# means 4223, the quiet dev broker).
nats_host = System.get_env("NATS_HOST", "localhost")
nats_port = System.get_env("NATS_PORT", "4223") |> String.to_integer()

config :bot_army_library_runtime, :nats,
  servers: [{nats_host, nats_port}],
  ping_interval: 5000,
  max_reconnect_attempts: 3,
  reconnect_delay_ms: 100

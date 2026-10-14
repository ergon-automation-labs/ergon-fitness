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
# BotArmyLibraryRuntime.NATS.Connection resolves servers in this order:
# explicit opts -> this app config -> NATS_PORT in the environment -> the
# fail-safe default of the dev broker (localhost:4223). It DOES read
# NATS_HOST/NATS_PORT itself (Connection.servers_from_env/0), but app config
# beats the environment, so this block is what decides where the bot goes and
# a bot that omits it lands on the dev broker no matter what the plist says.
# Deploy plists opt a bot into production with NATS_PORT=4222 (fail-safe policy:
# unset env means 4223, the quiet dev broker).
#
# The environment read here is not only the shell's: config/config.exs loads a
# repo-root .env with System.put_env/2, so a value in .env overrides one the
# process was started with -- including NATS_PORT=42991 on a test run. A test
# suite that looks hermetic can therefore be talking to the live broker. See
# docs/runbooks/KNOWN_ISSUE_DOTENV_IN_VM_OVERRIDES_THE_TEST_BROKER.md.
nats_host = System.get_env("NATS_HOST", "localhost")
nats_port = System.get_env("NATS_PORT", "4223") |> String.to_integer()

config :bot_army_library_runtime, :nats,
  servers: [{nats_host, nats_port}],
  ping_interval: 5000,
  max_reconnect_attempts: 3,
  reconnect_delay_ms: 100

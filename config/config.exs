import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "[$time] [$level] $message\n",
  metadata: [:correlation_id]

config :bot_army_fitness, :deployment_status, "experimental"
# Load .env for local development — never under :test. `.env` is gitignored and carries
# `NATS_PORT=4222`; `System.put_env/2` writes the VM's own env table, which is exactly
# what `Connection.pick_servers/2` reads (opts -> app config -> env -> default), so a
# shell-exported `NATS_PORT=42991` is overwritten *inside the VM* and cannot save a run.
# On 2026-10-13 a `mix test` in this repo published a real `gossip.social.invite` into
# gtd's production log that way.
# docs/runbooks/KNOWN_ISSUE_DOTENV_IN_VM_OVERRIDES_THE_TEST_BROKER.md
if config_env() != :test and File.exists?(".env") do
  File.stream!(".env")
  |> Stream.map(&String.trim_trailing/1)
  |> Stream.reject(&String.starts_with?(&1, "#"))
  |> Stream.reject(&(&1 == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(key, value)
      _ -> nil
    end
  end)
end

# Ecto repositories for migrations
config :bot_army_fitness, ecto_repos: [BotArmyFitness.Repo]

# Intent thresholds for fitness heartbeat decisions
config :bot_army_fitness, :intent_thresholds, %{
  idle_minutes: %{min: 60, weight: 0.7},
  streak_at_risk: %{min: 1, weight: 0.3},
  random_threshold: 0.4
}

# Database configuration — defaults only, overridden by config/runtime.exs at startup
config :bot_army_fitness, BotArmyFitness.Repo,
  database: "ergon_fitness",
  hostname: "localhost",
  port: 30003,
  username: "postgres",
  password: "postgres",
  pool_size: 10

# Import environment-specific config
if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end


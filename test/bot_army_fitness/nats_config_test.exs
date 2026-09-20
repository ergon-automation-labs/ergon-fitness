defmodule BotArmyFitness.NatsConfigTest do
  use ExUnit.Case

  @moduletag :core

  # BotArmyLibraryRuntime.NATS.Connection resolves its server list from app
  # config only:
  #
  #   opts[:servers] -> Application.get_env(:bot_army_library_runtime, :nats)[:servers]
  #     -> @default_servers (the dev broker, port 4223)
  #
  # It does NOT read NATS_HOST / NATS_PORT / NATS_SERVERS itself. So a bot that
  # omits the `:nats` block in config/runtime.exs silently joins the dev broker,
  # and the deploy plist's NATS_PORT=4222 has no effect (this is exactly how
  # fitness ended up subscribed on 4223 while the dashboard asked 4222).
  #
  # These tests pin the contract that runtime.exs sets the block from the
  # environment, so NATS_PORT from the plist is what decides the broker.

  test "runtime config derives NATS servers from the environment" do
    servers = Application.get_env(:bot_army_library_runtime, :nats)[:servers]

    expected_host = System.get_env("NATS_HOST", "localhost")
    expected_port = System.get_env("NATS_PORT", "4223") |> String.to_integer()

    assert [{^expected_host, ^expected_port}] = servers
  end

  test "the bot does not fall through to the library's fail-safe default" do
    # nil servers would mean the library default (4223) applies regardless of
    # what the plist sets, which is the failure mode these tests guard.
    assert Application.get_env(:bot_army_library_runtime, :nats)[:servers] != nil
  end
end

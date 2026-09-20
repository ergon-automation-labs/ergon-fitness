defmodule BotArmyFitness.PulsePublisherTest do
  use ExUnit.Case, async: true

  @moduletag :core

  alias BotArmyFitness.PulsePublisher
  alias BotArmyLibraryCore.NATS.Decoder

  describe "gossip_envelope/1" do
    test "satisfies the shared decoder so the tavern feed is not dropped" do
      envelope = PulsePublisher.gossip_envelope("🫀 Two workouts logged this week.")

      assert {:ok, decoded} = Decoder.decode(Jason.encode!(envelope))

      assert decoded["event"] == "gossip.tavern.narrated"
      assert decoded["source"] == "fitness_bot"
      assert is_binary(decoded["source_node"]) and decoded["source_node"] != ""
      assert decoded["triggered_by"] == "scheduler"
      assert decoded["payload"]["text"] == "🫀 Two workouts logged this week."
    end
  end
end

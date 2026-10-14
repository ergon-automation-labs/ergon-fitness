defmodule BotArmyFitness.PulsePublisherTest do
  use ExUnit.Case

  @moduletag :core

  import Mox

  alias BotArmyFitness.PulsePublisher
  alias BotArmyLibraryCore.NATS.Decoder

  setup :set_mox_global

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

  describe "build_pulse_payload/1" do
    test "carries the days since the last workout, read from the store" do
      stub_workouts({:ok, [%{"id" => "w-1", "date" => Date.add(Date.utc_today(), -6)}]})

      observations = PulsePublisher.build_pulse_payload(idle_metrics())["observations"]

      assert observations["days_since_workout"] == 6
      assert observations["idle_minutes"] == 60
      assert observations["streak_at_risk"] == 0
    end

    test "omits the observation when the store cannot be read" do
      stub_workouts({:error, :timeout})

      payload = PulsePublisher.build_pulse_payload(idle_metrics())

      # Not 0 ("worked out today") and not 999 ("never worked out") — an absent key
      # is the only honest encoding of "we could not look". extract_observations/1
      # reads an absent key as 0, so a store outage stays quiet.
      refute Map.has_key?(payload["observations"], "days_since_workout")
      assert payload["observations"]["idle_minutes"] == 60
    end

    test "reports the never-worked-out sentinel as a real observation" do
      stub_workouts({:ok, []})

      assert PulsePublisher.build_pulse_payload(idle_metrics())["observations"][
               "days_since_workout"
             ] == 999
    end

    test "still reports the health signal and counters it always has" do
      stub_workouts({:ok, []})

      payload = PulsePublisher.build_pulse_payload(idle_metrics())

      assert payload["service"] == "fitness"
      assert payload["health_signal"] == "degraded"
      assert payload["metrics"] == %{"workouts" => 0, "streak_days" => 0, "active_goals" => 0}
    end
  end

  defp stub_workouts(reply) do
    stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> reply end)
    stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> {:ok, []} end)
  end

  defp idle_metrics, do: %{workouts: 0, streak_days: 0, active_goals: 0}
end

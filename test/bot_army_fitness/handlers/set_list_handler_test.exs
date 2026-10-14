defmodule BotArmyFitness.Handlers.SetListHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Handlers.SetListHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  setup do
    stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> {:ok, []} end)
    :ok
  end

  describe "handle_list/1" do
    test "answers the sets the store returned, with their count and the limit asked for" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn @tenant, 10 ->
        {:ok, [set_row("2026-10-14"), set_row("2026-10-10")]}
      end)

      reply = decode(SetListHandler.handle_list(request(%{})))

      assert reply["ok"] == true
      assert reply["data"]["count"] == 2
      assert reply["data"]["limit"] == 10
      assert Enum.map(reply["data"]["sets"], & &1["date"]) == ["2026-10-14", "2026-10-10"]
    end

    test "reads the limit from a flat body as well as from a payload" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn @tenant, 3 -> {:ok, []} end)

      flat =
        request(%{"limit" => 3})
        |> Map.delete("payload")
        |> Map.merge(%{"limit" => 3})

      assert %{"limit" => 3} = decode(SetListHandler.handle_list(flat))["data"]

      assert %{"limit" => 3} =
               decode(SetListHandler.handle_list(request(%{"limit" => 3})))["data"]
    end

    test "a limit that is not a whole number above zero falls back to the default ten" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn @tenant, 10 -> {:ok, []} end)

      for limit <- [0, -1, 2.5, "ten", nil] do
        assert %{"limit" => 10} =
                 decode(SetListHandler.handle_list(request(%{"limit" => limit})))[
                   "data"
                 ]
      end
    end

    test "a store that cannot answer is a refusal, not an empty log" do
      # This is the difference between this verb and `fitness.workout.list`: an empty
      # list and an unreadable one must not look the same, or the card below says she has
      # logged nothing when the truth is that nobody asked successfully.
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(SetListHandler.handle_list(request(%{})))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
    end

    test "an unexpected store reply is a refusal too, and names what it got" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> :no_reply end)

      reply = decode(SetListHandler.handle_list(request(%{})))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
    end
  end

  # Same workspace contract as the other schema-parity tests: the schemas repo is a
  # sibling checkout, and the bot is the side that must not drift from it.
  describe "parity with the published schema" do
    test "the reply's only refusal is the one the handler utters" do
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.set.list.reply.json")

      [_ok, refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")

      assert refused["properties"]["code"]["enum"] == ["read_failed"]
    end
  end

  defp request(payload) do
    %{
      "event" => "fitness.set.list",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => payload
    }
  end

  defp set_row(date) do
    %{
      "id" => UUID.uuid4(),
      "exercise" => "kb_swing",
      "measure" => "reps",
      "amount" => 12,
      "load_kind" => "kg",
      "load_value" => 24.5,
      "date" => date
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

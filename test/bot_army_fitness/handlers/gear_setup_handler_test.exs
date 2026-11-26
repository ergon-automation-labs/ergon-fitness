defmodule BotArmyFitness.Handlers.GearSetupHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Gear
  alias BotArmyFitness.Handlers.GearSetupHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  describe "handle_setup/1" do
    test "raises the cable to the wall, and answers with the state it wrote" do
      expect(BotArmyFitness.GearSetupStoreMock, :put, fn @tenant, "wall" -> {:ok, "wall"} end)

      reply = decode(GearSetupHandler.handle_setup(request(%{"maxpro" => "wall"})))

      assert reply["ok"] == true
      assert reply["data"]["gear"]["maxpro"] == "wall"
    end

    test "accepts the field under either name the card and the plan use" do
      stub(BotArmyFitness.GearSetupStoreMock, :put, fn @tenant, "floor" -> {:ok, "floor"} end)

      reply = decode(GearSetupHandler.handle_setup(request(%{"position" => "floor"})))

      assert reply["data"]["gear"]["maxpro"] == "floor"
    end

    test "a word the room cannot be is refused, and the refusal names both real ones" do
      reply = decode(GearSetupHandler.handle_setup(request(%{"maxpro" => "attached"})))

      assert reply["ok"] == false
      assert reply["code"] == "bad_position"
      assert reply["error"] =~ "floor"
      assert reply["error"] =~ "wall"
    end

    test "the words it accepts are the catalog's list, not a copy of it" do
      # The rule the whole gear change rests on: the door's vocabulary and the plan's are
      # one list. A door that accepted a third word would write a state no plan can read.
      refused = decode(GearSetupHandler.handle_setup(request(%{"maxpro" => "basement"})))

      assert refused["code"] == "bad_position"
      assert Gear.positions() == ["floor", "wall"]
    end

    test "a write that fails is a failure, not a silent plan for the old room" do
      stub(BotArmyFitness.GearSetupStoreMock, :put, fn _tenant, _pos ->
        {:error, :database_error}
      end)

      reply = decode(GearSetupHandler.handle_setup(request(%{"maxpro" => "wall"})))

      assert reply["ok"] == false
      assert reply["code"] == "persist_failed"
    end

    test "a store that raises still answers" do
      stub(BotArmyFitness.GearSetupStoreMock, :put, fn _tenant, _pos ->
        raise "could not lookup Ecto repo"
      end)

      assert decode(GearSetupHandler.handle_setup(request(%{"maxpro" => "wall"})))["ok"] == false
    end
  end

  defp request(payload) do
    %{
      "event" => "fitness.gear.setup",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => payload
    }
  end

  defp decode(reply), do: Jason.decode!(reply)
end

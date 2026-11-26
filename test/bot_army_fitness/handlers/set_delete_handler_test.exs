defmodule BotArmyFitness.Handlers.SetDeleteHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Handlers.SetDeleteHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  describe "handle_delete/1" do
    test "takes back the set it was told to, and answers with the row as it now stands" do
      expect(BotArmyFitness.WorkoutSetStoreMock, :delete, fn @tenant, "set-1" ->
        {:ok, taken_back("set-1")}
      end)

      reply = decode(SetDeleteHandler.handle_delete(request("set-1")))

      assert reply["ok"] == true
      assert reply["data"]["set"]["id"] == "set-1"
      assert reply["data"]["set"]["deleted_at"] == "2026-11-25T12:00:00Z"
    end

    test "an id that is not in her log is a refusal, never an empty success" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :delete, fn _tenant, _id ->
        {:error, :not_found}
      end)

      reply = decode(SetDeleteHandler.handle_delete(request("set-elsewhere")))

      assert reply["ok"] == false
      assert reply["error"] == "that set is not in your log"
    end

    test "no id is a refusal that names the missing fact, not a guess at the last set" do
      reply = decode(SetDeleteHandler.handle_delete(request(nil)))

      assert reply["ok"] == false
      assert reply["error"] == "no set was named"
      assert reply["code"] == "missing_set"
    end

    test "a store that fails to write answers failed, and does not claim the set is gone" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :delete, fn _tenant, _id ->
        {:error, :database_error}
      end)

      reply = decode(SetDeleteHandler.handle_delete(request("set-1")))

      assert reply["ok"] == false
      assert reply["code"] == "persist_failed"
    end

    test "a store that raises answers, because a handler that crashes is a request that hangs" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :delete, fn _tenant, _id ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(SetDeleteHandler.handle_delete(request("set-1")))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
    end

    test "reads the flat body as well as the enveloped one" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :delete, fn @tenant, "set-1" ->
        {:ok, taken_back("set-1")}
      end)

      flat =
        request("set-1")
        |> Map.delete("payload")
        |> Map.put("id", "set-1")

      assert decode(SetDeleteHandler.handle_delete(flat))["ok"] == true
    end
  end

  defp request(id) do
    %{
      "event" => "fitness.set.delete",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => if(id, do: %{"id" => id}, else: %{})
    }
  end

  defp taken_back(id) do
    %{
      "id" => id,
      "exercise" => "kb_swing",
      "amount" => 12,
      "deleted_at" => "2026-11-25T12:00:00Z"
    }
  end

  defp decode(reply), do: Jason.decode!(reply)
end

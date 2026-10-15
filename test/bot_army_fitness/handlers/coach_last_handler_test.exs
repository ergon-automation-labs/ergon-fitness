defmodule BotArmyFitness.Handlers.CoachLastHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Handlers.CoachLastHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  setup do
    stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant -> {:ok, nil} end)
    :ok
  end

  describe "handle_last/1" do
    test "a log with nothing in it is a fact, not a refusal, and names no day" do
      reply = decode(CoachLastHandler.handle_last(request()))

      assert reply["ok"] == true
      assert reply["data"] == %{"day" => nil, "movements" => [], "count" => 0}
      refute reply["data"]["day"]
    end

    test "one entry per movement, in the order she last touched them" do
      # Two sets of the kettlebell in the day and one pull-up. The kettlebell is touched
      # most recently, so it comes first; the older kettlebell set is the same movement and
      # is not a second entry. A surface would otherwise draw the same movement twice and
      # have to decide for itself which row is "last", which is the bot's job.
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn @tenant ->
        {:ok,
         %{
           "date" => "2026-10-14",
           "sets" => [
             set("goblet_squat", "reps", 8, "kg", 11.5),
             set("pull_up", "reps", 5, "bodyweight", nil),
             set("goblet_squat", "reps", 10, "kg", 11.5)
           ]
         }}
      end)

      reply = decode(CoachLastHandler.handle_last(request()))

      assert reply["ok"] == true
      assert reply["data"]["day"] == "2026-10-14"
      assert reply["data"]["count"] == 2

      assert reply["data"]["movements"] == [
               %{
                 "value" => "goblet_squat",
                 "measure" => "reps",
                 "amount" => 8,
                 "load_kind" => "kg",
                 "load_value" => 11.5
               },
               %{
                 "value" => "pull_up",
                 "measure" => "reps",
                 "amount" => 5,
                 "load_kind" => "bodyweight",
                 "load_value" => nil
               }
             ]
    end

    test "a hold keeps its seconds, and a bodyweight movement keeps its null load" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn @tenant ->
        {:ok,
         %{
           "date" => "2026-10-14",
           "sets" => [set("dip_hold_top", "seconds", 20, "bodyweight", nil)]
         }}
      end)

      movement = decode(CoachLastHandler.handle_last(request()))["data"]["movements"] |> hd()

      assert movement["measure"] == "seconds"
      assert movement["amount"] == 20
      assert movement["load_kind"] == "bodyweight"
      assert is_nil(movement["load_value"])
    end

    test "a store that cannot be read is a refusal, not an empty log" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(CoachLastHandler.handle_last(request()))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
      refute reply["data"]
    end

    test "an unexpected store reply is a refusal too" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant -> :no_reply end)

      assert decode(CoachLastHandler.handle_last(request()))["code"] == "read_failed"
    end

    test "a day that arrives without its sets is a refusal, not a day with no movements" do
      # The store's contract is day and rows together. A day with no rows would let the card
      # draw "you did nothing that day", which is the one thing this read must never invent.
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant ->
        {:ok, %{"date" => "2026-10-14"}}
      end)

      assert decode(CoachLastHandler.handle_last(request()))["code"] == "read_failed"
    end

    test "reads the request's tenant, and both shapes of body answer alike" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn @tenant ->
        {:ok, %{"date" => "2026-10-14", "sets" => [set("pull_up", "reps", 5, "bodyweight", nil)]}}
      end)

      flat = Map.delete(request(), "payload")

      assert decode(CoachLastHandler.handle_last(flat))["data"] ==
               decode(CoachLastHandler.handle_last(request()))["data"]
    end
  end

  # Same workspace contract as the other schema-parity tests: the schemas repo is a
  # sibling checkout and the bot is the side that must not drift from it.
  describe "parity with the published schema" do
    test "the refusal code the handler utters is the only one the reply allows" do
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.coach.last.reply.json")

      [_ok, refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")

      assert refused["properties"]["code"]["enum"] == ["read_failed"]
    end
  end

  defp request do
    %{
      "event" => "fitness.coach.last",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{}
    }
  end

  defp set(exercise, measure, amount, load_kind, load_value) do
    %{
      "id" => UUID.uuid4(),
      "exercise" => exercise,
      "measure" => measure,
      "amount" => amount,
      "load_kind" => load_kind,
      "load_value" => load_value,
      "date" => "2026-10-14"
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

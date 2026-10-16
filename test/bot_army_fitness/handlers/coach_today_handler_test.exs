defmodule BotArmyFitness.Handlers.CoachTodayHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Coach
  alias BotArmyFitness.Handlers.CoachTodayHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  # The day count is a union of the two logs, so every test here answers for both stores:
  # the workout log (nothing by default) and the set log's days. The history read is a
  # third stub, and it is the one the tests about numbers override.
  #
  # The day itself is pinned to the method's anchor, so the suite means the same thing at
  # midnight and on a machine in another zone. A test that cares which day it is pins another
  # one with `pin_day/1`.
  setup do
    pin_day(Coach.rotation_anchor())

    stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
    stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> {:ok, []} end)

    stub(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn _tenant, _ex ->
      {:ok, %{}}
    end)

    :ok
  end

  describe "handle_today/1" do
    test "answers the anchor's session for a log with nothing in it, and says what day it is for" do
      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["ok"] == true

      assert reply["data"]["rotation"] == %{
               "length" => 4,
               "position" => 0,
               "days_trained" => 0,
               "date" => Date.to_iso8601(Coach.rotation_anchor())
             }

      assert reply["data"]["session"]["value"] == "push_a"
      assert length(reply["data"]["session"]["slots"]) == 6
    end

    test "the day count travels beside the session, and no longer decides it" do
      # Three distinct training days, four sets on one of them and a workout on another: the
      # count is a fact about her log and the card still says it. What changed is that it no
      # longer *is* the rotation — the session is the day's, so the same log answers a
      # different session tomorrow with the same count beside it. That is the reported bug:
      # "today's session" did not change when the day did.
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn @tenant ->
        {:ok, [~D[2026-10-05], ~D[2026-10-05], ~D[2026-10-08]]}
      end)

      stub(BotArmyFitness.WorkoutStoreMock, :list, fn @tenant ->
        {:ok, [%{"date" => ~D[2026-10-09]}]}
      end)

      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["data"]["rotation"]["days_trained"] == 3
      assert reply["data"]["rotation"]["position"] == 0
      assert reply["data"]["session"]["value"] == "push_a"

      pin_day(Date.add(Coach.rotation_anchor(), 1))
      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["data"]["rotation"]["days_trained"] == 3
      assert reply["data"]["rotation"]["position"] == 1
      assert reply["data"]["session"]["value"] == "pull_a"
    end

    test "the day on the wire is the house's day, not UTC's" do
      # A day at the tail of the year in the house's own zone, and a different one in UTC:
      # if the handler read the clock itself this would answer two days in one run.
      day = ~D[2026-12-31]
      pin_day(day)

      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["data"]["rotation"]["date"] == "2026-12-31"
      assert reply["data"]["rotation"]["position"] == Coach.position(day)
    end

    test "a day counts once even when both logs hold it" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn @tenant ->
        {:ok, [~D[2026-10-05]]}
      end)

      stub(BotArmyFitness.WorkoutStoreMock, :list, fn @tenant ->
        {:ok, [%{"date" => ~D[2026-10-05]}]}
      end)

      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["data"]["rotation"]["days_trained"] == 1
    end

    test "an unreadable day count is a refusal, not a first session" do
      # The whole point of the read failing being visible: "Push A" here would be the bot
      # deciding she has never trained because a database hiccup looked like an empty log.
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
      refute reply["data"]["session"]
    end

    test "an unexpected day-count reply is a refusal too" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> :no_reply end)

      assert decode(CoachTodayHandler.handle_today(request()))["code"] == "read_failed"
    end

    test "a history that cannot be read is a refusal, not a session with no numbers" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn _tenant, _ex ->
        {:error, :timeout}
      end)

      reply = decode(CoachTodayHandler.handle_today(request()))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
    end

    test "asks the store only for the movements this session offers" do
      session = Coach.owed_on(Coach.rotation_anchor())

      expected =
        session["slots"] |> Enum.flat_map(& &1["options"]) |> Enum.uniq()

      expect(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn @tenant, movements ->
        assert movements == expected
        assert length(movements) < length(Coach.movements())
        {:ok, %{}}
      end)

      assert decode(CoachTodayHandler.handle_today(request()))["ok"] == true
    end

    test "her own next number reaches the movement line, and the rest stay empty" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn _tenant, _ex ->
        {:ok, %{"cable_chest_press" => [set("cable_chest_press", "2026-10-13", 8, 10)]}}
      end)

      session = decode(CoachTodayHandler.handle_today(request()))["data"]["session"]

      press =
        session["slots"]
        |> List.first()
        |> Map.fetch!("movements")
        |> Enum.find(&(&1["value"] == "cable_chest_press"))

      assert press["next"] == %{
               "exercise" => "cable_chest_press",
               "measure" => "reps",
               "amount" => 10,
               "load_kind" => "level",
               "load_value" => 10
             }

      assert press["last"] == "2026-10-13"

      assert session["slots"] |> List.first() |> Map.fetch!("recent") == "cable_chest_press"
    end

    test "reads the request's tenant, and both shapes of body answer alike" do
      flat = Map.delete(request(), "payload")

      assert decode(CoachTodayHandler.handle_today(flat))["data"]["session"] ==
               decode(CoachTodayHandler.handle_today(request()))["data"]["session"]

      assert decode(CoachTodayHandler.handle_today(flat))["data"]["session"]["value"] ==
               "push_a"
    end
  end

  # Same workspace contract as the other schema-parity tests: the schemas repo is a
  # sibling checkout and the bot is the side that must not drift from it.
  describe "parity with the published schema" do
    test "the refusal code the handler utters is the only one the reply allows" do
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.coach.today.reply.json")

      [_ok, refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")

      assert refused["properties"]["code"]["enum"] == ["read_failed"]
    end

    test "the day rides on the rotation without being required, so an older reply still validates" do
      # The compatibility rule this change was written under, in one assertion: `"date"` is
      # additive. A caller that predates it ignores it, a reply that predates it omits it, and
      # neither side refuses the other over a field that only labels the answer.
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.coach.today.reply.json")

      [ok, _refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")
      rotation = ok["properties"]["data"]["properties"]["rotation"]

      assert rotation["required"] == ["length", "position", "days_trained"]
      assert rotation["properties"]["date"]["format"] == "date"
    end
  end

  defp pin_day(day) do
    Application.put_env(:bot_army_fitness, :household_today, fn -> day end)
    on_exit(fn -> Application.delete_env(:bot_army_fitness, :household_today) end)
  end

  defp request do
    %{
      "event" => "fitness.coach.today",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{}
    }
  end

  defp set(exercise, date, amount, load_value) do
    %{
      "id" => UUID.uuid4(),
      "exercise" => exercise,
      "measure" => "reps",
      "amount" => amount,
      "load_kind" => "level",
      "load_value" => load_value,
      "date" => date
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

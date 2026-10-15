defmodule BotArmyFitness.Handlers.CoachChatHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Handlers.CoachChatHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  setup do
    stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
    stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> {:ok, []} end)

    stub(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn _tenant, _ex ->
      {:ok, %{}}
    end)

    stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant -> {:ok, nil} end)
    :ok
  end

  describe "handle_chat/2" do
    test "a question with nobody to answer is dropped, not answered into the void" do
      assert CoachChatHandler.handle_chat(request(), nil) == :ok
      assert CoachChatHandler.handle_chat(request(), "") == :ok
    end
  end

  describe "context/1" do
    test "gathers today's session, the day count that turns it, and her last day" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn @tenant ->
        {:ok, [~D[2026-10-05]]}
      end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn @tenant ->
        {:ok,
         %{"date" => "2026-10-14", "sets" => [set("kb_swing"), set("kb_swing"), set("pull_up")]}}
      end)

      context = CoachChatHandler.context(@tenant)

      assert context.days_trained == 1
      assert context.today["value"] == "pull_a"
      assert context.today["slots"] != []

      # One entry per movement, and the store's `"exercise"` spelled as the movement's value
      # so the words above it never have to know which store the row came from.
      assert context.last["day"] == "2026-10-14"
      assert Enum.map(context.last["movements"], & &1["value"]) == ["kb_swing", "pull_up"]
    end

    test "a log with nothing in it is `nil`, which is a fact and not a failure" do
      assert CoachChatHandler.context(@tenant).last == nil
    end

    test "a store that cannot be read is `:unreadable`, not an empty log" do
      # The one distinction this context exists to carry: a database hiccup must never reach the
      # words above as "she has kept nothing".
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant ->
        raise "could not lookup Ecto repo"
      end)

      assert CoachChatHandler.context(@tenant).last == :unreadable
    end

    test "an unexpected store reply is `:unreadable` too" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn _tenant -> :no_reply end)

      assert CoachChatHandler.context(@tenant).last == :unreadable
    end

    test "an unreadable day count silences the session but not the log" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        raise "could not lookup Ecto repo"
      end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent_day, fn @tenant ->
        {:ok, %{"date" => "2026-10-14", "sets" => [set("pull_up")]}}
      end)

      context = CoachChatHandler.context(@tenant)

      assert context.today == nil
      assert context.days_trained == nil
      assert context.last["day"] == "2026-10-14"
    end

    test "an unreadable history silences the session's numbers but keeps the room answerable" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :newest_per_exercise, fn _tenant, _ex ->
        raise "could not lookup Ecto repo"
      end)

      assert CoachChatHandler.context(@tenant).today == nil
    end
  end

  describe "reply_payload/1" do
    test "an answer is the coach's words under the ok envelope" do
      reply = CoachChatHandler.reply_payload({:ok, "the row is a back movement"}) |> decode()

      assert reply["ok"] == true
      assert reply["data"] == %{"response" => "the row is a back movement"}
    end

    test "no question is a refusal with a sentence of its own" do
      reply = CoachChatHandler.reply_payload({:error, :missing_message}) |> decode()

      assert reply["ok"] == false
      assert reply["code"] == "missing_message"
      assert reply["error"] == "ask the coach a question"
    end

    test "a model that could not be reached is a refusal, never an invented answer" do
      for reason <- [:timeout, :no_responders, {:invalid_response, nil}] do
        reply = CoachChatHandler.reply_payload({:error, reason}) |> decode()

        assert reply["ok"] == false
        assert reply["code"] == "llm_failed"
        assert reply["error"] == "the coach could not answer just now"
        refute reply["data"]
      end
    end
  end

  # Same workspace contract as the other schema-parity tests: the schemas repo is a sibling
  # checkout and the bot is the side that must not drift from it.
  describe "parity with the published schema" do
    test "the refusal codes the handler utters are the only ones the reply allows" do
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.coach.chat.reply.json")

      [_ok, refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")

      assert refused["properties"]["code"]["enum"] == ["missing_message", "llm_failed"]
    end
  end

  defp request do
    %{
      "event" => "fitness.coach.chat",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{"message" => "what does the cable row work?"}
    }
  end

  defp set(exercise) do
    %{
      "id" => UUID.uuid4(),
      "exercise" => exercise,
      "measure" => "reps",
      "amount" => 8,
      "load_kind" => "bodyweight",
      "load_value" => nil,
      "date" => "2026-10-14"
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

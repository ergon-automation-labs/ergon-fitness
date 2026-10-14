defmodule BotArmyFitness.Handlers.SetRecordHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.Handlers.SetRecordHandler

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  setup do
    stub(BotArmyFitness.WorkoutSetStoreMock, :create, fn payload ->
      {:ok, stored_set(payload)}
    end)

    stub(BotArmyFitness.WorkoutSetStoreMock, :previous_for_exercise, fn _tenant, _exercise ->
      {:ok, nil}
    end)

    :ok
  end

  describe "validate/1 — the movement's own menu is the menu" do
    test "accepts a dumbbell set on the equipment's own ladder" do
      assert {:ok, %{exercise: exercise, amount: 12, load_value: 25.0}} =
               SetRecordHandler.validate(%{
                 "exercise" => "goblet_squat",
                 "amount" => 12,
                 "load" => 25
               })

      assert exercise["measure"] == "reps"
    end

    test "accepts a kettlebell set at one of the seven settings" do
      assert {:ok, %{load_value: 24.5}} =
               SetRecordHandler.validate(%{
                 "exercise" => "kb_swing",
                 "amount" => 12,
                 "load" => 24.5
               })
    end

    test "refuses a weight the equipment does not have, rather than rounding it" do
      # The kettlebell's settings are 5, 11.5, 18, 24.5, 31, 37.5, 44. Accepting 24
      # would store a set that never happened, and the next read would build a
      # progression on a weight that does not exist.
      assert {:error, :load_not_on_ladder} =
               SetRecordHandler.validate(%{"exercise" => "kb_swing", "amount" => 10, "load" => 24})
    end

    test "refuses a weight above what the dumbbells can hold" do
      # The dumbbells stop at 55 kg each ("max pro" is the machine; this is the rack).
      assert {:error, :load_not_on_ladder} =
               SetRecordHandler.validate(%{
                 "exercise" => "goblet_squat",
                 "amount" => 10,
                 "load" => 60
               })
    end

    test "accepts the top of the dumbbell ladder" do
      assert {:ok, %{load_value: 55.0}} =
               SetRecordHandler.validate(%{
                 "exercise" => "goblet_squat",
                 "amount" => 5,
                 "load" => 55
               })
    end

    test "accepts a MaxPRO level, which is a dial position and not a weight" do
      assert {:ok, %{load_value: 12.0}} =
               SetRecordHandler.validate(%{
                 "exercise" => "cable_chest_press",
                 "amount" => 10,
                 "load" => 12
               })
    end

    test "refuses a MaxPRO level past the clutch, which locks at 25" do
      assert {:error, :load_not_on_ladder} =
               SetRecordHandler.validate(%{
                 "exercise" => "cable_chest_press",
                 "amount" => 10,
                 "load" => 26
               })
    end

    test "accepts a bodyweight movement with no number at all" do
      assert {:ok, %{load_value: nil}} =
               SetRecordHandler.validate(%{"exercise" => "pull_up", "amount" => 8})
    end

    test "accepts a negative number on a bodyweight movement — that is an assist" do
      assert {:ok, %{load_value: -20.0}} =
               SetRecordHandler.validate(%{"exercise" => "pull_up", "amount" => 8, "load" => -20})
    end

    test "refuses a movement this gym does not have" do
      assert {:error, :unknown_movement} =
               SetRecordHandler.validate(%{"exercise" => "cable_crossover", "amount" => 10})
    end

    test "refuses a missing movement" do
      assert {:error, :missing_exercise} = SetRecordHandler.validate(%{"amount" => 10})
    end

    test "refuses a rep count that is not a whole number above zero" do
      assert {:error, :amount_not_a_count} =
               SetRecordHandler.validate(%{"exercise" => "kb_swing", "amount" => 0})

      assert {:error, :amount_not_a_count} =
               SetRecordHandler.validate(%{"exercise" => "kb_swing", "amount" => 7.5})

      assert {:error, :amount_not_a_count} =
               SetRecordHandler.validate(%{"exercise" => "kb_swing", "amount" => "twelve"})
    end

    test "accepts twelve written as a float, because that is a spelling and not a wrong count" do
      assert {:ok, %{amount: 12}} =
               SetRecordHandler.validate(%{"exercise" => "kb_swing", "amount" => 12.0})
    end

    test "refuses a measure the movement does not take, by deriving it instead of trusting the caller" do
      # A dead hang is measured in seconds; a caller saying "reps" is describing the
      # movement, and describing a movement is the catalog's job.
      assert {:ok, %{exercise: exercise}} =
               SetRecordHandler.validate(%{"exercise" => "dead_hang", "amount" => 30})

      assert exercise["measure"] == "seconds"
    end
  end

  describe "handle_record/1" do
    test "records the set and answers with it" do
      reply = decode(SetRecordHandler.handle_record(request("goblet_squat", 12, 25)))

      assert reply["ok"] == true
      assert reply["data"]["set"]["exercise"] == "goblet_squat"
      assert reply["data"]["set"]["amount"] == 12
      assert reply["data"]["set"]["load_value"] == 25.0
      assert reply["data"]["set"]["load_kind"] == "kg"
      assert reply["data"]["set"]["measure"] == "reps"
    end

    test "answers with the previous set for the same movement, so a card can say last time" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :previous_for_exercise, fn _tenant, "kb_swing" ->
        {:ok,
         %{"amount" => 12, "load_value" => 24.5, "load_kind" => "kg", "date" => "2026-10-10"}}
      end)

      reply = decode(SetRecordHandler.handle_record(request("kb_swing", 10, 31)))

      assert reply["data"]["previous"]["load_value"] == 24.5
      assert reply["data"]["previous"]["amount"] == 12
    end

    test "answers with a refusal, not an :ok, when the weight is off the ladder" do
      reply = decode(SetRecordHandler.handle_record(request("kb_swing", 10, 24)))

      assert reply["ok"] == false
      assert reply["code"] == "load_not_on_ladder"
      assert reply["error"] =~ "settings"
    end

    test "reads a flat body, not only one wrapped in payload" do
      flat =
        request("goblet_squat", 12, 25)
        |> Map.delete("payload")
        |> Map.merge(%{"exercise" => "goblet_squat", "amount" => 12, "load" => 25})

      reply = decode(SetRecordHandler.handle_record(flat))

      assert reply["ok"] == true
      assert reply["data"]["set"]["amount"] == 12
    end

    test "stores the movement's own measure and kind rather than the caller's words" do
      test_pid = self()

      stub(BotArmyFitness.WorkoutSetStoreMock, :create, fn payload ->
        send(test_pid, {:stored, payload})
        {:ok, stored_set(payload)}
      end)

      decode(SetRecordHandler.handle_record(request("dead_hang", 30, nil)))

      assert_received {:stored, payload}
      assert payload["measure"] == "seconds"
      assert payload["load_kind"] == "bodyweight"
      assert payload["tenant_id"] == @tenant
    end

    test "a store that cannot answer becomes a refusal, not a crashed consumer" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :create, fn _payload ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(SetRecordHandler.handle_record(request("kb_swing", 10, 31)))

      assert reply["ok"] == false
      assert reply["code"] == "persist_failed"
    end
  end

  # Same workspace contract as the catalog's schema-parity tests: the schemas repo
  # is a sibling checkout, and the bot is the side that must not drift from it.
  @schema_path Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)

  describe "parity with the published schema" do
    test "the reply's measure and load_kind enums are the catalog's" do
      [ok, _refused] = read_schema("fitness.set.record.reply.json")["oneOf"]
      set = ok["properties"]["data"]["properties"]["set"]

      assert set["properties"]["measure"]["enum"] == ExerciseCatalog.measures()
      assert set["properties"]["load_kind"]["enum"] == ExerciseCatalog.load_kinds()
    end

    test "every refusal the bot can utter is in the schema" do
      [_ok, refused] = read_schema("fitness.set.record.reply.json")["oneOf"]

      # The handler's codes are the refusal's own words. A code the bot emits that
      # the schema does not list is a refusal a caller cannot classify.
      for code <- ~w(missing_exercise unknown_movement amount_not_a_count
                    load_not_on_ladder load_not_a_number persist_failed) do
        assert code in refused["properties"]["code"]["enum"],
               "#{code} is emitted by the handler but missing from the schema"
      end
    end

    test "there is an example of a bodyweight set with no load" do
      path = Path.join(@schema_path, "../examples/fitness.set.record.reply.first.json")
      body = path |> File.read!() |> Jason.decode!()

      assert body["data"]["set"]["load_kind"] == "bodyweight"
      assert body["data"]["set"]["load_value"] == nil
      assert body["data"]["previous"] == nil
    end

    defp read_schema(name) do
      @schema_path |> Path.join(name) |> File.read!() |> Jason.decode!()
    end
  end

  defp request(exercise, amount, load) do
    %{
      "event" => "fitness.set.record",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{"exercise" => exercise, "amount" => amount, "load" => load}
    }
  end

  defp stored_set(payload) do
    %{
      "id" => UUID.uuid4(),
      "tenant_id" => payload["tenant_id"],
      "user_id" => payload["user_id"],
      "exercise" => payload["exercise"],
      "measure" => payload["measure"],
      "amount" => payload["amount"],
      "load_kind" => payload["load_kind"],
      "load_value" => payload["load_value"],
      "date" => Date.to_iso8601(Date.utc_today())
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

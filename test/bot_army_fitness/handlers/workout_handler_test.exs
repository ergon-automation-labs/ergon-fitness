defmodule BotArmyFitness.Handlers.WorkoutHandlerTest do
  use ExUnit.Case
  @moduletag :handlers
  import Mox

  setup :set_mox_global

  setup do
    stub(BotArmyFitness.WorkoutStoreMock, :create, fn _payload ->
      {:ok, %{"id" => UUID.uuid4(), "title" => "test workout"}}
    end)

    :ok
  end

  describe "handle_log/1" do
    test "successfully logs a workout and answers with the written workout" do
      reply = decode(BotArmyFitness.Handlers.WorkoutHandler.handle_log(valid_log_message()))

      assert reply["ok"] == true
      assert reply["data"]["workout_type"] == "running"
      assert reply["data"]["duration_minutes"] == 30
      assert reply["data"]["workout_id"]
      assert reply["schema_version"] == "1.0"
    end

    test "answers with a refusal instead of `:ok` for a missing workout_type" do
      reply =
        valid_log_message()
        |> put_in(["payload", "workout_type"], nil)
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["ok"] == false
      assert reply["code"] == "validation_error"
      assert reply["error"] =~ "workout_type"
    end

    test "answers with a refusal for a missing duration_minutes" do
      reply =
        valid_log_message()
        |> put_in(["payload", "duration_minutes"], nil)
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["ok"] == false
      assert reply["error"] =~ "duration_minutes"
    end

    test "accepts the fields at the top level, not only under payload" do
      # The consumer's request/reply decode path merges the body at the top level
      # and only sets "event". Reading only message["payload"] silently dropped
      # every such body, which is why the verb had no producers.
      flat = %{
        "event" => "fitness.workout.log",
        "tenant_id" => "00000000-0000-0000-0000-000000000001",
        "user_id" => "user-1",
        "workout_type" => "swimming",
        "duration_minutes" => 45
      }

      reply = flat |> BotArmyFitness.Handlers.WorkoutHandler.handle_log() |> decode()

      assert reply["ok"] == true
      assert reply["data"]["workout_type"] == "swimming"
      assert reply["data"]["duration_minutes"] == 45
    end

    test "accepts optional calories_burned field" do
      reply =
        valid_log_message()
        |> put_in(["payload", "calories_burned"], 500)
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["ok"] == true
    end

    test "accepts optional intensity field" do
      reply =
        valid_log_message()
        |> put_in(["payload", "intensity"], "high")
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["ok"] == true
      # "high" is folded onto the one canonical intensity list
      assert reply["data"]["intensity"] == "intense"
    end

    test "defaults intensity to moderate when the log does not carry one" do
      reply =
        valid_log_message()
        |> put_in(["payload", "intensity"], nil)
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["data"]["intensity"] == "moderate"
    end

    test "requires both required fields" do
      reply =
        valid_log_message()
        |> put_in(["payload", "workout_type"], nil)
        |> put_in(["payload", "duration_minutes"], nil)
        |> then(&BotArmyFitness.Handlers.WorkoutHandler.handle_log/1)
        |> decode()

      assert reply["ok"] == false
    end

    test "folds every workout type onto the one canonical vocabulary" do
      for {sent, canonical} <- [
            {"running", "running"},
            {"cycling", "cycling"},
            {"swimming", "swimming"},
            {"weight_training", "strength"},
            {"yoga", "yoga"},
            {"pushups", "other"}
          ] do
        message = valid_log_message() |> put_in(["payload", "workout_type"], sent)

        reply =
          message
          |> BotArmyFitness.Handlers.WorkoutHandler.handle_log()
          |> decode()

        assert reply["ok"] == true
        assert reply["data"]["workout_type"] == canonical
      end
    end

    test "keeps the human's own word in the title when the type is unknown" do
      parent = self()

      stub(BotArmyFitness.WorkoutStoreMock, :create, fn payload ->
        send(parent, {:stored, payload})
        {:ok, %{"id" => UUID.uuid4(), "title" => payload["title"], "date" => "2026-03-01"}}
      end)

      valid_log_message()
      |> put_in(["payload", "workout_type"], "pushups")
      |> BotArmyFitness.Handlers.WorkoutHandler.handle_log()

      assert_received {:stored, stored}
      assert stored["exercise_type"] == "other"
      assert stored["title"] == "pushups"
    end

    test "accepts different duration values" do
      for duration <- [15, 30, 45, 60, 120] do
        message = valid_log_message() |> put_in(["payload", "duration_minutes"], duration)

        reply =
          message
          |> BotArmyFitness.Handlers.WorkoutHandler.handle_log()
          |> decode()

        assert reply["ok"] == true
        assert reply["data"]["duration_minutes"] == duration
      end
    end

    test "refuses honestly when the store fails, instead of claiming success" do
      stub(BotArmyFitness.WorkoutStoreMock, :create, fn _payload -> {:error, :db_down} end)

      reply =
        valid_log_message()
        |> BotArmyFitness.Handlers.WorkoutHandler.handle_log()
        |> decode()

      assert reply["ok"] == false
      assert reply["code"] == "persist_failed"
    end

    test "stores exercise_type from workout_type and keeps calories" do
      parent = self()

      stub(BotArmyFitness.WorkoutStoreMock, :create, fn payload ->
        send(parent, {:stored, payload})
        {:ok, %{"id" => UUID.uuid4(), "title" => payload["title"], "date" => "2026-03-01"}}
      end)

      reply =
        valid_log_message()
        |> BotArmyFitness.Handlers.WorkoutHandler.handle_log()
        |> decode()

      assert_received {:stored, stored}
      assert stored["exercise_type"] == "running"
      assert stored["calories"] == 300
      # `valid_log_message/0` carries `"user_id" => nil`, so the tenant default applies
      assert stored["user_id"] == BotArmyLibraryCore.Tenant.default_user_id()
      assert reply["data"]["date"] == "2026-03-01"
    end
  end

  describe "handle_options/1" do
    test "answers with the activities and intensities a picker may offer" do
      reply = BotArmyFitness.Handlers.WorkoutHandler.handle_options() |> decode()

      assert reply["ok"] == true

      assert reply["data"]["workout_types"] ==
               Enum.map(BotArmyFitness.WorkoutTypes.types(), fn type ->
                 %{"value" => type, "label" => BotArmyFitness.WorkoutTypes.label(type)}
               end)

      assert reply["data"]["intensities"] ==
               Enum.map(BotArmyFitness.WorkoutTypes.intensities(), fn level ->
                 %{
                   "value" => level,
                   "label" => BotArmyFitness.WorkoutTypes.intensity_label(level)
                 }
               end)
    end

    test "does not offer `other` — it is a stored value, not an activity" do
      reply = BotArmyFitness.Handlers.WorkoutHandler.handle_options(%{}) |> decode()

      values = Enum.map(reply["data"]["workout_types"], & &1["value"])

      assert values == BotArmyFitness.WorkoutTypes.types()
      refute "other" in values
      assert "other" in BotArmyFitness.WorkoutTypes.values()
    end

    test "every option carries the bot's own word for it" do
      reply = BotArmyFitness.Handlers.WorkoutHandler.handle_options() |> decode()

      for group <- ["workout_types", "intensities"], option <- reply["data"][group] do
        assert option["label"] not in [nil, ""]
        assert option["label"] != option["value"]
      end
    end
  end

  describe "list_response/1" do
    test "unwraps the store's tagged tuple instead of raising (regression)" do
      # WorkoutStore.list/1 replies {:ok, workouts}. Treating that tuple as a
      # list raised Protocol.UndefinedError, which terminated the consumer and
      # dropped every fitness NATS subscription (fitness.workout.list never
      # replied).
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout("w-1", "user-1", "2026-01-01")]}
      end)

      response = BotArmyFitness.Handlers.WorkoutHandler.list_response(list_message())

      assert response["count"] == 1
      assert [%{"id" => "w-1"}] = response["workouts"]
    end

    test "only returns workouts belonging to the requesting user" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok,
         [
           workout("mine", "user-1", "2026-01-02"),
           workout("theirs", "user-2", "2026-01-03")
         ]}
      end)

      response = BotArmyFitness.Handlers.WorkoutHandler.list_response(list_message())

      assert response["count"] == 1
      assert [%{"id" => "mine"}] = response["workouts"]
    end

    test "sorts by date descending" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok,
         [
           workout("older", "user-1", "2026-01-01"),
           workout("newer", "user-1", "2026-02-01"),
           workout("middle", "user-1", "2026-01-15")
         ]}
      end)

      response = BotArmyFitness.Handlers.WorkoutHandler.list_response(list_message())

      assert Enum.map(response["workouts"], & &1["id"]) == ["newer", "middle", "older"]
    end

    test "honours the requested limit and echoes it" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok,
         [
           workout("a", "user-1", "2026-01-04"),
           workout("b", "user-1", "2026-01-03"),
           workout("c", "user-1", "2026-01-02")
         ]}
      end)

      response =
        BotArmyFitness.Handlers.WorkoutHandler.list_response(
          list_message(%{"payload" => %{"limit" => 2}})
        )

      assert response["limit"] == 2
      assert response["count"] == 2
      assert Enum.map(response["workouts"], & &1["id"]) == ["a", "b"]
    end

    test "degrades to an empty list when the store fails instead of crashing" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:error, :store_down} end)

      response = BotArmyFitness.Handlers.WorkoutHandler.list_response(list_message())

      assert response == %{"workouts" => [], "count" => 0, "limit" => 10}
    end

    test "defaults limit when the request carries no payload" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      response =
        BotArmyFitness.Handlers.WorkoutHandler.list_response(list_message(%{"payload" => nil}))

      assert response == %{"workouts" => [], "count" => 0, "limit" => 10}
    end

    test "honours a flat limit, not only one nested under payload (regression)" do
      # The consumer's request/reply path merges the body at the top level, so a
      # surface's `{"limit": 20}` arrives as `%{"limit" => 20}` and never as
      # `%{"payload" => ...}`. Reading only "payload" ignored every such limit
      # and answered with the default ten.
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout("a", "user-1", "2026-01-04"), workout("b", "user-1", "2026-01-03")]}
      end)

      response =
        BotArmyFitness.Handlers.WorkoutHandler.list_response(%{
          "event" => "fitness.workout.list",
          "tenant_id" => "00000000-0000-0000-0000-000000000001",
          "user_id" => "user-1",
          "limit" => 1
        })

      assert response["limit"] == 1
      assert response["count"] == 1
      assert Enum.map(response["workouts"], & &1["id"]) == ["a"]
    end

    test "handle_list/2 is silent when there is no reply subject" do
      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_list(%{}, "")
      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_list(%{}, nil)
    end
  end

  # Helper functions

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)

  defp list_message(overrides \\ %{}) do
    Map.merge(
      %{
        "event" => "fitness.workout.list",
        "tenant_id" => "00000000-0000-0000-0000-000000000001",
        "user_id" => "user-1",
        "payload" => %{}
      },
      overrides
    )
  end

  defp workout(id, user_id, date) do
    %{"id" => id, "user_id" => user_id, "date" => date}
  end

  defp valid_log_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "fitness.workout.log",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "tenant_id" => "00000000-0000-0000-0000-000000000001",
      "user_id" => nil,
      "payload" => %{
        "workout_type" => "running",
        "duration_minutes" => 30,
        "intensity" => "moderate",
        "calories_burned" => 300
      }
    }
  end
end

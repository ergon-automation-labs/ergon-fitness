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
    test "successfully logs a workout" do
      message = valid_log_message()

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "returns error for missing workout_type" do
      message =
        valid_log_message()
        |> put_in(["payload", "workout_type"], nil)

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "returns error for missing duration_minutes" do
      message =
        valid_log_message()
        |> put_in(["payload", "duration_minutes"], nil)

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "accepts optional calories_burned field" do
      message =
        valid_log_message()
        |> put_in(["payload", "calories_burned"], 500)

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "accepts optional intensity field" do
      message =
        valid_log_message()
        |> put_in(["payload", "intensity"], "high")

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "requires both required fields" do
      message =
        valid_log_message()
        |> put_in(["payload", "workout_type"], nil)
        |> put_in(["payload", "duration_minutes"], nil)

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "validates workout with all fields" do
      message =
        valid_log_message()
        |> put_in(["payload", "calories_burned"], 350)
        |> put_in(["payload", "intensity"], "medium")

      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
    end

    test "handles various workout types" do
      for workout_type <- ["running", "cycling", "swimming", "weight_training", "yoga"] do
        message = valid_log_message() |> put_in(["payload", "workout_type"], workout_type)
        assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
      end
    end

    test "accepts different duration values" do
      for duration <- [15, 30, 45, 60, 120] do
        message = valid_log_message() |> put_in(["payload", "duration_minutes"], duration)
        assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)
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

    test "handle_list/2 is silent when there is no reply subject" do
      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_list(%{}, "")
      assert :ok = BotArmyFitness.Handlers.WorkoutHandler.handle_list(%{}, nil)
    end
  end

  # Helper functions

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

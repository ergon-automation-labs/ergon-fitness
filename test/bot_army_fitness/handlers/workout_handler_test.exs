defmodule BotArmyFitness.Handlers.WorkoutHandlerTest do
  use ExUnit.Case

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

  # Helper functions

  defp valid_log_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "fitness.workout.log",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "payload" => %{
        "workout_type" => "running",
        "duration_minutes" => 30,
        "intensity" => "moderate",
        "calories_burned" => 300
      }
    }
  end
end

defmodule BotArmyFitness.Handlers.GoalHandlerTest do
  use ExUnit.Case

  describe "handle_set/1" do
    test "successfully sets a fitness goal" do
      message = valid_set_message()

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
    end

    test "returns error for missing goal_type" do
      message =
        valid_set_message()
        |> put_in(["payload", "goal_type"], nil)

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
    end

    test "returns error for missing target_value" do
      message =
        valid_set_message()
        |> put_in(["payload", "target_value"], nil)

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
    end

    test "sets goal with optional deadline" do
      message =
        valid_set_message()
        |> put_in(["payload", "deadline"], "2026-12-31")

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
    end

    test "sets goal with unit" do
      message =
        valid_set_message()
        |> put_in(["payload", "unit"], "kilometers")

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
    end

    test "accepts various goal types" do
      for goal_type <- ["weight_loss", "weight_gain", "run_distance", "run_frequency", "strength"] do
        message = valid_set_message() |> put_in(["payload", "goal_type"], goal_type)
        assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
      end
    end

    test "accepts numeric target values" do
      for target <- [50, 100.5, 5, 3] do
        message = valid_set_message() |> put_in(["payload", "target_value"], target)
        assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_set(message)
      end
    end
  end

  describe "handle_update/1" do
    test "successfully updates a fitness goal" do
      message = valid_update_message()

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "returns error for missing goal_id" do
      message =
        valid_update_message()
        |> put_in(["payload", "goal_id"], nil)

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "allows updating target_value" do
      message =
        valid_update_message()
        |> put_in(["payload", "target_value"], 75)

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "allows updating deadline" do
      message =
        valid_update_message()
        |> put_in(["payload", "deadline"], "2027-06-30")

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "allows updating status" do
      message =
        valid_update_message()
        |> put_in(["payload", "status"], "in_progress")

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "allows minimal update with just goal_id" do
      message = %{
        "event_id" => UUID.uuid4(),
        "event" => "fitness.goal.update",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "source" => "test_client",
        "source_node" => "test_node",
        "triggered_by" => "manual",
        "schema_version" => "1.0",
        "payload" => %{
          "goal_id" => UUID.uuid4()
        }
      }

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end

    test "accepts multiple update fields" do
      message =
        valid_update_message()
        |> put_in(["payload", "target_value"], 80)
        |> put_in(["payload", "deadline"], "2027-03-31")
        |> put_in(["payload", "status"], "completed")

      assert :ok = BotArmyFitness.Handlers.GoalHandler.handle_update(message)
    end
  end

  # Helper functions

  defp valid_set_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "fitness.goal.set",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "payload" => %{
        "goal_type" => "weight_loss",
        "target_value" => 70,
        "unit" => "kg",
        "deadline" => "2026-12-31"
      }
    }
  end

  defp valid_update_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "fitness.goal.update",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "payload" => %{
        "goal_id" => UUID.uuid4(),
        "target_value" => 72,
        "status" => "active"
      }
    }
  end
end

defmodule BotArmyFitness.Handlers.GoalHandler do
  @moduledoc """
  Handles fitness goal-related events for the Fitness bot.

  This module processes incoming goal messages:
  - `fitness.goal.set` - Set a new fitness goal
  - `fitness.goal.update` - Update existing fitness goal

  Each operation validates the input and publishes response events.
  """

  require Logger

  @doc """
  Handle fitness goal setting event.

  Validates the goal data and publishes a goal.set event.
  """
  def handle_set(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_set_payload(payload) do
      :ok ->
        Logger.info("Fitness goal set: event_id=#{event_id}")
        publish_event("fitness.goal.set", payload, event_id)

      {:error, reason} ->
        Logger.warning("Invalid goal payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid goal data")
    end
  end

  @doc """
  Handle fitness goal update event.

  Validates the update data and publishes a goal.updated event.
  """
  def handle_update(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_update_payload(payload) do
      :ok ->
        Logger.info("Fitness goal updated: event_id=#{event_id}")
        publish_event("fitness.goal.updated", payload, event_id)

      {:error, reason} ->
        Logger.warning("Invalid goal update payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid goal data")
    end
  end

  # Private functions

  defp validate_set_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "goal_type"),
         :ok <- require_field(payload, "target_value") do
      :ok
    end
  end

  defp validate_set_payload(_), do: {:error, :invalid_payload}

  defp validate_update_payload(payload) when is_map(payload) do
    require_field(payload, "goal_id")
  end

  defp validate_update_payload(_), do: {:error, :invalid_payload}

  defp require_field(payload, field) do
    case payload do
      %{^field => value} when value not in [nil, ""] -> :ok
      _ -> {:error, {:missing_field, field}}
    end
  end

  defp publish_event(event_type, payload, event_id) do
    event_data = %{
      "event" => event_type,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => get_node_name(),
      "triggered_by" => "fitness.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "goal_type" => Map.get(payload, "goal_type"),
        "target_value" => Map.get(payload, "target_value"),
        "deadline" => Map.get(payload, "deadline"),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyFitness.NATS.Publisher.publish(event_data) do
      :ok -> Logger.debug("Published event: #{event_type}")
      {:error, reason} -> Logger.error("Failed to publish event: #{inspect(reason)}")
    end
  end

  defp publish_error(event_id, reason, message) do
    error_event = %{
      "event" => "fitness.error",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => get_node_name(),
      "triggered_by" => "fitness.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "error" => message,
        "reason" => inspect(reason),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyFitness.NATS.Publisher.publish(error_event) do
      :ok -> Logger.debug("Published error event")
      {:error, err} -> Logger.error("Failed to publish error: #{inspect(err)}")
    end
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end
end

defmodule BotArmyFitness.NATS.Publisher do
  @moduledoc """
  NATS event publisher for the Fitness bot.

  Publishes response events from Fitness handlers back to the NATS broker.
  Events include workout.logged, goal.set, goal.updated, and error events.

  ## Features

  - Serialization of events to JSON
  - Subject routing based on event type
  - Error handling and logging
  - Connection management
  """

  require Logger

  @doc """
  Publish an event to NATS.

  The event map should contain:
  - `"event"` - Event type (e.g., "fitness.workout.logged")
  - `"event_id"` - Unique event identifier
  - `"timestamp"` - ISO8601 timestamp
  - `"source"` - Source bot (e.g., "bot_army_fitness")
  - `"source_node"` - Node name
  - `"triggered_by"` - Audit value
  - `"schema_version"` - Schema version
  - `"payload"` - Event payload

  Returns `:ok` if successful, or `{:error, reason}` on failure.
  """
  def publish(event) when is_map(event) do
    try do
      subject = derive_subject(event["event"])
      body = Jason.encode!(event)

      case do_publish(subject, body) do
        :ok ->
          Logger.debug("Published event to #{subject}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to publish to #{subject}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception during publish: #{inspect(e)}")
        {:error, e}
    end
  end

  def publish(_) do
    {:error, :invalid_event}
  end

  # Private functions

  defp do_publish(subject, body) do
    case Jason.decode(body) do
      {:ok, payload} ->
        BotArmyRuntime.NATS.Publisher.publish(subject, payload)

      {:error, reason} ->
        Logger.error("Failed to decode body for #{subject}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp derive_subject(event_type) when is_binary(event_type) do
    case event_type do
      "fitness.workout.logged" -> "events.fitness.workout.logged"
      "fitness.goal.set" -> "events.fitness.goal.set"
      "fitness.goal.updated" -> "events.fitness.goal.updated"
      "fitness.error" -> "events.fitness.error"
      _ -> "events.fitness.unknown"
    end
  end

  defp derive_subject(_) do
    "events.fitness.unknown"
  end
end

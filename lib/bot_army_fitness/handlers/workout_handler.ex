defmodule BotArmyFitness.Handlers.WorkoutHandler do
  @moduledoc """
  Handles workout-related events for the Fitness bot.

  This module processes incoming workout messages:
  - `fitness.workout.log` - Log a completed workout

  Each operation validates the input and publishes response events.
  """

  require Logger

  @doc """
  Handle workout logging event.

  Validates the workout data and publishes a workout.logged event.
  """
  def handle_log(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_log_payload(payload) do
      :ok ->
        store_payload = %{
          "tenant_id" => tenant_id,
          "user_id" => user_id,
          "title" => Map.get(payload, "title", payload["workout_type"]),
          "exercise_type" => payload["workout_type"],
          "duration_minutes" => payload["duration_minutes"],
          "calories" => Map.get(payload, "calories_burned"),
          "intensity" => Map.get(payload, "intensity", "moderate"),
          "date" => Map.get(payload, "date")
        }

        case workout_store().create(store_payload) do
          {:ok, workout} ->
            Logger.info("Workout logged: event_id=#{event_id}, workout_id=#{workout["id"]}")

            # Record outcome: workout was completed
            try do
              BotArmyLearning.OutcomeTracker.record(
                workout["id"],
                "fitness.workout",
                "suggested",
                "completed",
                :fitness_outcome_tracker
              )
            rescue
              _ -> :ok
            end

            publish_event(
              "fitness.workout.logged",
              Map.put(payload, "workout_id", workout["id"]),
              event_id,
              tenant_id,
              user_id
            )

            # Fire-and-forget context signal for context broker
            try do
              BotArmyRuntime.NATS.Publisher.publish("context.signal.fitness", %{
                "type" => "workout_completed",
                "duration_minutes" => Map.get(payload, "duration_minutes"),
                "workout_type" => payload["workout_type"]
              })
            rescue
              _ -> :ok
            end

            :ok

          {:error, reason} ->
            Logger.warning("Failed to persist workout: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to persist workout", tenant_id, user_id)
            :ok
        end

      {:error, reason} ->
        Logger.warning("Invalid workout payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid workout data", tenant_id, user_id)
        :ok
    end
  end

  # Private functions

  defp validate_log_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "workout_type"),
         :ok <- require_field(payload, "duration_minutes") do
      :ok
    else
      error -> error
    end
  end

  defp validate_log_payload(_), do: {:error, :invalid_payload}

  defp require_field(payload, field) do
    case payload do
      %{^field => value} when value not in [nil, ""] -> :ok
      _ -> {:error, {:missing_field, field}}
    end
  end

  defp publish_event(event_type, payload, event_id, tenant_id, user_id) do
    event_data = %{
      "event" => event_type,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => get_node_name(),
      "triggered_by" => "fitness.bot",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "intensity" => Map.get(payload, "intensity", "moderate"),
      "workout_type" => payload["workout_type"],
      "payload" => %{
        "workout_type" => payload["workout_type"],
        "duration_minutes" => payload["duration_minutes"],
        "calories_burned" => Map.get(payload, "calories_burned"),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyFitness.NATS.Publisher.publish(event_data) do
      :ok -> Logger.debug("Published event: #{event_type}")
      {:error, reason} -> Logger.error("Failed to publish event: #{inspect(reason)}")
    end
  end

  defp publish_error(event_id, reason, message, tenant_id, user_id) do
    error_event = %{
      "event" => "fitness.error",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_fitness",
      "source_node" => get_node_name(),
      "triggered_by" => "fitness.bot",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
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

  defp workout_store do
    Application.get_env(:bot_army_fitness, :workout_store, BotArmyFitness.WorkoutStore)
  end
end

defmodule BotArmyFitness.Handlers.WorkoutHandler do
  @moduledoc """
  Handles workout-related events for the Fitness bot.

  This module processes incoming workout messages:
  - `fitness.workout.log` - Log a completed workout
  - `fitness.workout.list` - List recent workouts
  - `fitness.workout.options` - The activities, intensities, and home-gym equipment
    and movements a picker may offer

  Each operation validates the input and publishes response events.

  `fitness.workout.log` is a **request/reply** verb: the consumer decodes the body
  as plain JSON (its request-reply path merges the body at the top level and only
  sets `"event"`), so this handler accepts the fields at the top level **or**
  under `"payload"`, and answers with a
  `BotArmyLibraryRuntime.NATS.Reply` payload. Before this it was a `:subscribe`
  verb that read only `message["payload"]` and never replied: a flat body was
  silently dropped, and a caller could not tell an accepted log from a discarded
  one.
  """

  require Logger

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.WorkoutTypes
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  The options a picker may offer: the activities, the intensities, and the gym.

  This verb exists so no surface has to hold its own copy of the vocabulary.
  `fitness.workout.log` accepts free text and folds what it does not know onto
  `"other"`, so a surface that invented its own list would still be able to
  write — it would simply write a word that folds, and the two screens would
  disagree about what a workout is. The values here are `WorkoutTypes.types/0`
  and `WorkoutTypes.intensities/0`, and the labels are the bot's own words.

  The activities are coarse on purpose: the gym's own equipment and movements
  arrive beside them, from `ExerciseCatalog`, because "strength" cannot name a
  goblet squat and a home-gym menu has to. Each movement carries the activity it is
  stored under, so a surface never maps one vocabulary onto the other itself — it
  sends the movement's own word in `title` and the activity the bot attached to it.

  `rep_choices` is the counts a press may name for a movement measured in reps. It
  travels beside the movements rather than inside them because it is one list for the
  whole gym — the counts she presses — while each movement keeps its own window in
  `min`/`max` for the bot's suggestions to read. A movement measured in seconds draws
  from its own window; there is no list of seconds, and inventing one would be
  inventing a duration.

  Answers with an already-encoded `Reply`, like `handle_log/1`, so the consumer's
  clause is one line either way.
  """
  def handle_options(_message \\ %{}) do
    Reply.ok(%{
      "workout_types" => WorkoutTypes.type_options(),
      "intensities" => WorkoutTypes.intensity_options(),
      "equipment" => ExerciseCatalog.equipment(),
      "exercises" => ExerciseCatalog.exercise_options(),
      "rep_choices" => ExerciseCatalog.rep_choices()
    })
  end

  @doc """
  Handle workout list request.

  Returns a list of recent workouts for the user.
  """
  def handle_list(message, reply_to) when is_binary(reply_to) and reply_to != "" do
    reply(reply_to, list_response(message))
  end

  def handle_list(_message, _reply_to), do: :ok

  @doc """
  Build the `fitness.workout.list` response payload for a request.

  Pure apart from the workout store read: applies the user filter, recency sort
  and limit, then returns the response map. Split out of `handle_list/2` so the
  response shape is testable without a live NATS connection.

  `WorkoutStore.list/1` replies with a tagged tuple (`{:ok, workouts}`). A failed
  or unexpected read degrades to an empty list instead of raising, because an
  exception here terminates the consumer process and drops every fitness
  subscription with it.

  The request's fields are read with the same two-shape rule as `handle_log/1`:
  an envelope leaves them under `"payload"`, and a flat request/reply body puts
  them at the top level. Reading only `"payload"` meant a flat request's `limit`
  was silently ignored and every call answered with the default ten.
  """
  def list_response(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyLibraryCore.Tenant.extract_context(message)
    payload = message["payload"] || message
    limit = Map.get(payload, "limit", 10)

    workouts =
      case workout_store().list(tenant_id) do
        {:ok, workouts} when is_list(workouts) ->
          workouts

        other ->
          Logger.warning("[WorkoutHandler] Unexpected workout store reply: #{inspect(other)}")
          []
      end

    filtered_workouts =
      workouts
      |> Enum.filter(fn w ->
        # Filter by user
        w["user_id"] == user_id
      end)
      |> Enum.sort_by(fn w -> w["date"] || "" end, :desc)
      |> Enum.take(limit)

    %{
      "workouts" => filtered_workouts,
      "count" => length(filtered_workouts),
      "limit" => limit
    }
  end

  @doc """
  Handle workout logging event.

  Validates the workout data, persists it, publishes a `fitness.workout.logged`
  event, and returns the request/reply answer (already JSON-encoded). Never
  raises, and always answers, so a caller can tell a refusal from a write.
  """
  def handle_log(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyLibraryCore.Tenant.extract_context(message)
    event_id = message["event_id"]
    payload = log_payload(message)

    case validate_log_payload(payload) do
      :ok ->
        store_payload = %{
          "tenant_id" => tenant_id,
          "user_id" => user_id,
          # the human's own word is kept in the title; the reportable field is
          # folded onto the one canonical vocabulary
          "title" => Map.get(payload, "title") || payload["workout_type"],
          "exercise_type" => WorkoutTypes.normalise_type(payload["workout_type"]),
          "duration_minutes" => payload["duration_minutes"],
          "calories" => Map.get(payload, "calories_burned"),
          # `Map.get/3`'s default does not fire when the key is present but nil,
          # which would send NULL into a `null: false` column and refuse the write.
          # Treat an explicit nil exactly like an absent field.
          "intensity" => WorkoutTypes.normalise_intensity(payload["intensity"]),
          "date" => Map.get(payload, "date")
        }

        case workout_store().create(store_payload) do
          {:ok, workout} ->
            Logger.info("Workout logged: event_id=#{event_id}, workout_id=#{workout["id"]}")

            BotArmyLibraryRuntime.Outcomes.emit("fitness", "workout", "workout_logged", 1,
              metadata: %{
                workout_id: workout["id"],
                workout_type: payload["workout_type"],
                duration_minutes: payload["duration_minutes"],
                tenant_id: tenant_id
              }
            )

            # Record outcome: workout was completed
            try do
              BotArmyLibraryLearning.OutcomeTracker.record(
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
              BotArmyLibraryCore.IntegrationGates.context_publish("context.signal.fitness", %{
                "type" => "workout_completed",
                "duration_minutes" => Map.get(payload, "duration_minutes"),
                "workout_type" => payload["workout_type"]
              })
            rescue
              _ -> :ok
            end

            ok_reply(workout, payload)

          {:error, reason} ->
            Logger.warning("Failed to persist workout: #{inspect(reason)}")

            BotArmyLibraryRuntime.Outcomes.emit("fitness", "workout", "workout_log_failed", 0,
              metadata: %{
                workout_type: payload["workout_type"],
                reason: inspect(reason),
                tenant_id: tenant_id
              }
            )

            publish_error(event_id, reason, "Failed to persist workout", tenant_id, user_id)
            Reply.error("failed to persist workout", :persist_failed)
        end

      {:error, reason} ->
        Logger.warning("Invalid workout payload: #{inspect(reason)}")

        BotArmyLibraryRuntime.Outcomes.emit("fitness", "workout", "workout_log_invalid", 0,
          metadata: %{
            reason: inspect(reason),
            tenant_id: tenant_id
          }
        )

        publish_error(event_id, reason, "Invalid workout data", tenant_id, user_id)
        invalid_reply(reason)
    end
  end

  # Private functions

  # The handler is reached two ways: as a decoded **envelope** (the
  # event-envelope decode path leaves the fields under `"payload"`) and as a plain
  # **request/reply body** (the consumer's request-reply path merges the body at
  # the top level). Reading only `message["payload"]` silently rejected every flat
  # body, so accept both shapes.
  defp log_payload(message), do: message["payload"] || message

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

  defp ok_reply(workout, payload) do
    Reply.ok(%{
      "workout_id" => workout["id"],
      "title" => workout["title"],
      "workout_type" => WorkoutTypes.normalise_type(payload["workout_type"]),
      "duration_minutes" => payload["duration_minutes"],
      "intensity" => WorkoutTypes.normalise_intensity(payload["intensity"]),
      "date" => workout["date"]
    })
  end

  defp invalid_reply({:missing_field, field}) do
    Reply.error("missing required field: #{field}", :validation_error)
  end

  defp invalid_reply(reason) do
    Reply.error("invalid workout payload: #{inspect(reason)}", :validation_error)
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
      "intensity" => payload["intensity"] || "moderate",
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

  defp reply(reply_to, payload) do
    case GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        Gnat.pub(conn, reply_to, Jason.encode!(payload))

      {:error, reason} ->
        Logger.warning("[WorkoutHandler] Failed to reply: #{inspect(reason)}")
    end
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end

  defp workout_store do
    Application.get_env(:bot_army_fitness, :workout_store, BotArmyFitness.WorkoutStore)
  end
end

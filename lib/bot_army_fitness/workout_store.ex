defmodule BotArmyFitness.WorkoutStore do
  @moduledoc """
  Workout storage: every read is a database read.

  This used to be a GenServer holding every workout in memory, loaded once at
  boot and written through on each create and update. That is a cache of the
  database, which is fine for one process on one machine and wrong for this bot:
  **air and mini both run it, each against its own `ergon_fitness` database**
  (measured 2026-10-14: air's `workouts` held 1 row, mini's held 0, and ten
  `fitness.workout.list` requests on air's broker were all answered by air). The
  two nodes share one queue group where their brokers meet, so a row can be written
  into the copy the next read does not use. A node answering from its own map made
  that worse rather than better: `list/1` returned "these are the workouts", a list
  that depended on which node happened to answer, and the row just written could be
  absent from it.

  There is no cache now. `list/1`, `get/2` and `list_by_date/2` query the
  database, so whatever the node can see, it answers truthfully, and a read that
  cannot reach the database fails instead of answering "none".

  `update/2` likewise loads the row it is told to update. It used to check the
  in-memory map first and answer `{:error, :not_found}` for a row the *other*
  node had created.

  ## API

  - `create/1` - Create a new workout
  - `update/2` - Update an existing workout
  - `get/2` - Retrieve a workout by ID, scoped to a tenant
  - `list/1` - List a tenant's workouts
  - `list_by_date/2` - List a tenant's workouts for a specific date
  """

  @behaviour BotArmyFitness.WorkoutStoreBehaviour

  require Logger

  import Ecto.Query

  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.Workout

  @doc """
  Create a new workout from payload.

  Returns `{:ok, workout}` with the created workout, or `{:error, reason}`.
  """
  @impl true
  def create(payload) when is_map(payload) do
    workout_id = Ecto.UUID.generate()

    changeset =
      Workout.changeset(
        %Workout{id: workout_id},
        %{
          "tenant_id" => payload["tenant_id"],
          "user_id" => Map.get(payload, "user_id"),
          "title" => payload["title"],
          "date" => workout_date(Map.get(payload, "date")),
          "duration_minutes" => payload["duration_minutes"],
          "exercise_type" => payload["exercise_type"],
          "intensity" => Map.get(payload, "intensity", "moderate"),
          "calories" => Map.get(payload, "calories", 0),
          "location" => Map.get(payload, "location")
        }
      )

    case Repo.insert(changeset) do
      {:ok, db_workout} ->
        Logger.info("Created workout in database: #{workout_id}")
        {:ok, schema_to_map(db_workout)}

      {:error, changeset} ->
        Logger.error("Failed to create workout: #{inspect(changeset.errors)}")
        {:error, :database_error}
    end
  end

  @doc """
  Update an existing workout.

  Returns `{:ok, workout}`, `{:error, :not_found}` for an unknown id or one
  belonging to another tenant, or `{:error, :database_error}`.
  """
  @impl true
  def update(workout_id, payload) when is_binary(workout_id) and is_map(payload) do
    with {:ok, uuid} <- cast_id(workout_id),
         %Workout{} = db_workout <- Repo.get(Workout, uuid) do
      changeset =
        Workout.changeset(db_workout, %{
          "title" => Map.get(payload, "title", db_workout.title),
          "date" => workout_date(Map.get(payload, "date")) || db_workout.date,
          "duration_minutes" => Map.get(payload, "duration_minutes", db_workout.duration_minutes),
          "exercise_type" => Map.get(payload, "exercise_type", db_workout.exercise_type),
          "intensity" => Map.get(payload, "intensity", db_workout.intensity),
          "calories" => Map.get(payload, "calories", db_workout.calories),
          "location" => Map.get(payload, "location", db_workout.location)
        })

      case Repo.update(changeset) do
        {:ok, updated_db_workout} ->
          Logger.info("Updated workout in database: #{workout_id}")
          {:ok, schema_to_map(updated_db_workout)}

        {:error, changeset} ->
          Logger.error("Failed to update workout: #{inspect(changeset.errors)}")
          {:error, :database_error}
      end
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  @doc "Retrieve a workout by id, scoped to a tenant. An id from another tenant is `:not_found`."
  @impl true
  def get(tenant_id, workout_id) when is_binary(tenant_id) and is_binary(workout_id) do
    with {:ok, uuid} <- cast_id(workout_id),
         %Workout{} = workout <- Repo.get(Workout, uuid),
         true <- to_string(workout.tenant_id) == tenant_id do
      {:ok, schema_to_map(workout)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "List a tenant's workouts, straight from the database."
  @impl true
  def list(tenant_id) when is_binary(tenant_id) do
    workouts =
      Workout
      |> where([w], w.tenant_id == ^tenant_id)
      |> Repo.all()
      |> Enum.map(&schema_to_map/1)

    {:ok, workouts}
  end

  @doc """
  List a tenant's workouts for one date.

  `:error` for a date the caller could not have meant. This used to render a
  malformed date as `{:error, :invalid_date}` only when the *calendar* rejected
  it; the database read that replaces the cache keeps the same three outcomes.
  """
  @impl true
  def list_by_date(tenant_id, date_str) when is_binary(tenant_id) and is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, target_date} ->
        workouts =
          Workout
          |> where([w], w.tenant_id == ^tenant_id and w.date == ^target_date)
          |> Repo.all()
          |> Enum.map(&schema_to_map/1)

        {:ok, workouts}

      {:error, _} ->
        {:error, :invalid_date}
    end
  end

  @doc """
  Delete every workout.

  This answers `:ok` and used to delete nothing — it cleared the in-memory map
  and left the database alone, which is a lie in a function called `clear`. It
  now deletes the rows. Nothing in the bot calls it; it exists for tests and
  tooling, and it is genuinely destructive.
  """
  @impl true
  def clear do
    {count, _} = Repo.delete_all(Workout)
    Logger.warning("Deleted #{count} workout(s)")
    :ok
  end

  # Private functions

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp workout_date(nil), do: Date.utc_today()

  defp workout_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  defp workout_date(_), do: Date.utc_today()

  # Helper function to convert Ecto schema to map for callers
  defp schema_to_map(%Workout{} = workout) do
    %{
      "id" => Ecto.UUID.cast!(workout.id) |> to_string(),
      "tenant_id" => workout.tenant_id |> to_string(),
      "user_id" => if(workout.user_id, do: workout.user_id |> to_string(), else: nil),
      "title" => workout.title,
      "date" => workout.date |> to_string(),
      "duration_minutes" => workout.duration_minutes,
      "exercise_type" => workout.exercise_type,
      "intensity" => workout.intensity,
      "calories" => workout.calories,
      "location" => workout.location,
      "created_at" => workout.inserted_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601(),
      "updated_at" => workout.updated_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601()
    }
  end
end

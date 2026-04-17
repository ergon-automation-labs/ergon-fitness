defmodule BotArmyFitness.WorkoutStore do
  @moduledoc """
  In-memory workout storage for the Fitness bot.

  This GenServer maintains the in-memory state of all workouts while Ecto handles
  persistence to PostgreSQL. On init, it loads all workouts from the database.
  Every mutation (create, update) is persisted to the database before updating state.

  ## API

  - `create/1` - Create a new workout
  - `update/2` - Update an existing workout
  - `get/1` - Retrieve a workout by ID
  - `list/0` - List all workouts
  - `list_by_date/1` - List workouts for a specific date
  """

  @behaviour BotArmyFitness.WorkoutStoreBehaviour

  use GenServer
  require Logger

  @server __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @doc """
  Create a new workout from payload.

  Returns `{:ok, workout}` with the created workout, or `{:error, reason}`.
  """
  def create(payload) when is_map(payload) do
    GenServer.call(@server, {:create, payload})
  end

  @doc """
  Update an existing workout.

  Returns `{:ok, workout}` with the updated workout, or `{:error, reason}`.
  """
  def update(workout_id, payload) when is_binary(workout_id) and is_map(payload) do
    GenServer.call(@server, {:update, workout_id, payload})
  end

  @doc """
  Retrieve a workout by ID.

  Returns `{:ok, workout}` or `{:error, :not_found}`.
  """
  def get(tenant_id, workout_id) when is_binary(tenant_id) and is_binary(workout_id) do
    GenServer.call(@server, {:get, tenant_id, workout_id})
  end

  @doc """
  List all workouts for a tenant.

  Returns `{:ok, workouts}`.
  """
  def list(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list, tenant_id})
  end

  @doc """
  List workouts for a specific date and tenant.

  Returns `{:ok, workouts}`.
  """
  def list_by_date(tenant_id, date_str) when is_binary(tenant_id) and is_binary(date_str) do
    GenServer.call(@server, {:list_by_date, tenant_id, date_str})
  end

  @doc """
  Clear all workouts (for testing).

  Returns `:ok`.
  """
  def clear do
    GenServer.call(@server, :clear)
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Logger.info("WorkoutStore started")
    # Load all workouts from database into GenServer state
    # Gracefully handle database unavailability (e.g., in tests)
    state =
      try do
        workouts = BotArmyFitness.Repo.all(BotArmyFitness.Schemas.Workout)

        Enum.reduce(workouts, %{}, fn workout, acc ->
          Map.put(acc, workout.id |> to_string(), schema_to_map(workout))
        end)
      rescue
        _ ->
          Logger.warning(
            "Could not load workouts from database (database unavailable). Starting with empty state."
          )

          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    workout_id = Ecto.UUID.generate()

    # Parse date if present
    workout_date =
      case Map.get(payload, "date") do
        nil ->
          Date.utc_today()

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            {:error, _} -> Date.utc_today()
          end

        _ ->
          Date.utc_today()
      end

    changeset =
      BotArmyFitness.Schemas.Workout.changeset(
        %BotArmyFitness.Schemas.Workout{id: workout_id},
        %{
          "tenant_id" => payload["tenant_id"],
          "user_id" => Map.get(payload, "user_id"),
          "title" => payload["title"],
          "date" => workout_date,
          "duration_minutes" => payload["duration_minutes"],
          "exercise_type" => payload["exercise_type"],
          "intensity" => Map.get(payload, "intensity", "moderate"),
          "calories" => Map.get(payload, "calories", 0),
          "location" => Map.get(payload, "location")
        }
      )

    case BotArmyFitness.Repo.insert(changeset) do
      {:ok, db_workout} ->
        workout = schema_to_map(db_workout)
        new_state = Map.put(state, workout_id, workout)
        Logger.info("Created workout in database: #{workout_id}")
        {:reply, {:ok, workout}, new_state}

      {:error, changeset} ->
        Logger.error("Failed to create workout: #{inspect(changeset.errors)}")
        {:reply, {:error, :database_error}, state}
    end
  end

  @impl true
  def handle_call({:update, workout_id, payload}, _from, state) do
    case Map.get(state, workout_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _workout ->
        workout_uuid = Ecto.UUID.cast!(workout_id)

        case BotArmyFitness.Repo.transaction(fn ->
               db_workout = BotArmyFitness.Repo.get(BotArmyFitness.Schemas.Workout, workout_uuid)

               if db_workout do
                 workout_date =
                   case Map.get(payload, "date") do
                     nil ->
                       nil

                     date_str when is_binary(date_str) ->
                       case Date.from_iso8601(date_str) do
                         {:ok, date} -> date
                         {:error, _} -> nil
                       end

                     _ ->
                       nil
                   end

                 changeset =
                   BotArmyFitness.Schemas.Workout.changeset(
                     db_workout,
                     %{
                       "title" => Map.get(payload, "title", db_workout.title),
                       "date" => workout_date || db_workout.date,
                       "duration_minutes" =>
                         Map.get(payload, "duration_minutes", db_workout.duration_minutes),
                       "exercise_type" =>
                         Map.get(payload, "exercise_type", db_workout.exercise_type),
                       "intensity" => Map.get(payload, "intensity", db_workout.intensity),
                       "calories" => Map.get(payload, "calories", db_workout.calories),
                       "location" => Map.get(payload, "location", db_workout.location)
                     }
                   )

                 case BotArmyFitness.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyFitness.Repo.rollback(changeset)
                 end
               else
                 BotArmyFitness.Repo.rollback(:not_found)
               end
             end) do
          {:ok, updated_db_workout} ->
            updated_workout = schema_to_map(updated_db_workout)
            new_state = Map.put(state, workout_id, updated_workout)
            Logger.info("Updated workout in database: #{workout_id}")
            {:reply, {:ok, updated_workout}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to update workout: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:get, tenant_id, workout_id}, _from, state) do
    case Map.get(state, workout_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      workout ->
        if workout["tenant_id"] == tenant_id do
          {:reply, {:ok, workout}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:list, tenant_id}, _from, state) do
    workouts =
      state
      |> Map.values()
      |> Enum.filter(&(&1["tenant_id"] == tenant_id))

    {:reply, {:ok, workouts}, state}
  end

  @impl true
  def handle_call({:list_by_date, tenant_id, date_str}, _from, state) do
    case Date.from_iso8601(date_str) do
      {:ok, target_date} ->
        workouts =
          state
          |> Map.values()
          |> Enum.filter(fn w ->
            w["tenant_id"] == tenant_id and w["date"] == target_date |> to_string()
          end)

        {:reply, {:ok, workouts}, state}

      {:error, _} ->
        {:reply, {:error, :invalid_date}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.debug("Clearing all workouts")
    {:reply, :ok, %{}}
  end

  # Helper function to convert Ecto schema to map for GenServer state
  defp schema_to_map(%BotArmyFitness.Schemas.Workout{} = workout) do
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
      "created_at" => workout.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => workout.updated_at |> NaiveDateTime.to_iso8601()
    }
  end
end

defmodule BotArmyFitness.GoalStore do
  @moduledoc """
  In-memory goal storage for the Fitness bot.

  This GenServer maintains the in-memory state of all fitness goals while Ecto handles
  persistence to PostgreSQL. On init, it loads all goals from the database.
  Every mutation (create, update) is persisted to the database before updating state.

  ## API

  - `create/1` - Create a new goal
  - `update/2` - Update an existing goal
  - `get/1` - Retrieve a goal by ID
  - `list/0` - List all goals
  - `clear/0` - Clear all goals (for testing)
  """

  use GenServer
  require Logger

  @server __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @doc """
  Create a new goal from payload.

  Returns `{:ok, goal}` with the created goal, or `{:error, reason}`.
  """
  def create(payload) when is_map(payload) do
    GenServer.call(@server, {:create, payload})
  end

  @doc """
  Update an existing goal.

  Returns `{:ok, goal}` with the updated goal, or `{:error, reason}`.
  """
  def update(goal_id, payload) when is_binary(goal_id) and is_map(payload) do
    GenServer.call(@server, {:update, goal_id, payload})
  end

  @doc """
  Retrieve a goal by ID.

  Returns `goal` or `nil`.
  """
  def get(goal_id) when is_binary(goal_id) do
    GenServer.call(@server, {:get, goal_id})
  end

  @doc """
  List all goals.

  Returns list of goals.
  """
  def list do
    GenServer.call(@server, :list)
  end

  @doc """
  Clear all goals (for testing).

  Returns `:ok`.
  """
  def clear do
    GenServer.call(@server, :clear)
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Logger.info("GoalStore started")
    # Load all goals from database into GenServer state
    # Gracefully handle database unavailability (e.g., in tests)
    state = try do
      goals = BotArmyFitness.Repo.all(BotArmyFitness.Schemas.Goal)
      Enum.reduce(goals, %{}, fn goal, acc ->
        Map.put(acc, goal.id |> to_string(), schema_to_map(goal))
      end)
    rescue
      _ ->
        Logger.warning("Could not load goals from database (database unavailable). Starting with empty state.")
        %{}
    end
    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    try do
      changeset = BotArmyFitness.Schemas.Goal.changeset(%BotArmyFitness.Schemas.Goal{}, payload)
      case BotArmyFitness.Repo.insert(changeset) do
        {:ok, goal} ->
          goal_map = schema_to_map(goal)
          new_state = Map.put(state, goal.id |> to_string(), goal_map)
          {:reply, {:ok, goal_map}, new_state}

        {:error, reason} ->
          Logger.warning("Failed to create goal: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    rescue
      e ->
        Logger.error("Exception in create: #{inspect(e)}")
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_call({:update, goal_id, payload}, _from, state) do
    try do
      case BotArmyFitness.Repo.get(BotArmyFitness.Schemas.Goal, goal_id) do
        nil ->
          Logger.warning("Goal not found: #{goal_id}")
          {:reply, {:error, :not_found}, state}

        goal ->
          changeset = BotArmyFitness.Schemas.Goal.changeset(goal, payload)
          case BotArmyFitness.Repo.update(changeset) do
            {:ok, updated_goal} ->
              goal_map = schema_to_map(updated_goal)
              new_state = Map.put(state, goal_id, goal_map)
              {:reply, {:ok, goal_map}, new_state}

            {:error, reason} ->
              Logger.warning("Failed to update goal: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
      end
    rescue
      e ->
        Logger.error("Exception in update: #{inspect(e)}")
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_call({:get, goal_id}, _from, state) do
    goal = Map.get(state, goal_id)
    {:reply, goal, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    goals = state |> Map.values()
    {:reply, goals, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  # Private

  defp schema_to_map(goal) do
    %{
      "id" => goal.id |> to_string(),
      "title" => goal.title,
      "target_date" => goal.target_date,
      "status" => goal.status,
      "inserted_at" => goal.inserted_at,
      "updated_at" => goal.updated_at
    }
  end
end

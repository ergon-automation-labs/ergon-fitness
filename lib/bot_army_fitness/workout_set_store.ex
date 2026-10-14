defmodule BotArmyFitness.WorkoutSetStore do
  @moduledoc """
  Set storage: every read is a database read.

  The same rule `WorkoutStore` learned the hard way: **air and mini both run this
  bot and both point at the same `ergon_fitness` database**, and since the two
  nodes were put on one queue group each message goes to exactly one of them. A
  process holding sets in memory would answer "this is what you lifted" with a
  list that depended on which node happened to answer, and the other node's write
  would be invisible — so there is no cache here either, and a read that cannot
  reach the database fails instead of answering "no sets".

  ## API

  - `create/1` — store one set
  - `recent/2` — a tenant's sets, newest first (limit)
  - `for_exercise/3` — one movement's sets, newest first (limit)
  - `previous_for_exercise/2` — the set before the newest one, for a "last time" line
  - `clear/0` — delete every set (tests and tooling; genuinely destructive)
  """

  @behaviour BotArmyFitness.WorkoutSetStoreBehaviour

  require Logger

  import Ecto.Query

  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.WorkoutSet

  @default_limit 20

  @doc """
  Store one set from a payload already validated against the movement's own menu.

  Returns `{:ok, set}` or `{:error, :database_error}`. The caller validates; this
  module does not re-decide whether a set is allowed, so the one place that knows
  the gym stays the one place.
  """
  @impl true
  def create(payload) when is_map(payload) do
    set_id = Ecto.UUID.generate()

    changeset =
      WorkoutSet.changeset(
        %WorkoutSet{id: set_id},
        %{
          "tenant_id" => payload["tenant_id"],
          "user_id" => Map.get(payload, "user_id"),
          "exercise" => payload["exercise"],
          "measure" => payload["measure"],
          "amount" => payload["amount"],
          "load_kind" => payload["load_kind"],
          "load_value" => Map.get(payload, "load_value"),
          "date" => set_date(Map.get(payload, "date"))
        }
      )

    case Repo.insert(changeset) do
      {:ok, db_set} ->
        Logger.info("Recorded set in database: #{set_id}")
        {:ok, schema_to_map(db_set)}

      {:error, changeset} ->
        Logger.error("Failed to record set: #{inspect(changeset.errors)}")
        {:error, :database_error}
    end
  end

  @doc "A tenant's sets, newest first."
  @impl true
  def recent(tenant_id, limit \\ @default_limit) when is_binary(tenant_id) do
    {:ok,
     WorkoutSet
     |> where([s], s.tenant_id == ^tenant_id)
     |> order_by([s], desc: s.inserted_at)
     |> limit(^normalise_limit(limit))
     |> Repo.all()
     |> Enum.map(&schema_to_map/1)}
  end

  @doc "One movement's sets, newest first — the progression line, oldest last."
  @impl true
  def for_exercise(tenant_id, exercise, limit \\ @default_limit)
      when is_binary(tenant_id) and is_binary(exercise) do
    {:ok,
     WorkoutSet
     |> where([s], s.tenant_id == ^tenant_id and s.exercise == ^exercise)
     |> order_by([s], desc: s.inserted_at)
     |> limit(^normalise_limit(limit))
     |> Repo.all()
     |> Enum.map(&schema_to_map/1)}
  end

  @doc """
  The set immediately before the newest one for a movement, or `nil`.

  `previous_for_exercise/2` exists so a card can say *"last time"* without
  fetching a whole history and slicing it in the surface: "the set before this one"
  is a database question, and a surface that computed it would be holding a copy of
  the rule about which set counts.
  """
  @impl true
  def previous_for_exercise(tenant_id, exercise)
      when is_binary(tenant_id) and is_binary(exercise) do
    case for_exercise(tenant_id, exercise, 2) do
      {:ok, [_newest]} -> {:ok, nil}
      {:ok, [_newest, previous | _]} -> {:ok, previous}
      {:ok, []} -> {:ok, nil}
    end
  end

  @doc """
  Delete every set.

  Answers `:ok` and deletes the rows. Nothing in the bot calls it; it exists for
  tests and tooling, and it is genuinely destructive.
  """
  @impl true
  def clear do
    {count, _} = Repo.delete_all(WorkoutSet)
    Logger.warning("Deleted #{count} set(s)")
    :ok
  end

  # Private functions

  defp normalise_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalise_limit(_other), do: @default_limit

  defp set_date(%Date{} = date), do: date

  defp set_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  # The day convention is this bot's (`Date.utc_today()`), the same one
  # `WorkoutStore.workout_date/1` uses, so "days since the last workout" cannot
  # disagree with itself about which day a set landed on.
  defp set_date(_other), do: Date.utc_today()

  defp schema_to_map(%WorkoutSet{} = set) do
    %{
      "id" => set.id |> to_string(),
      "tenant_id" => set.tenant_id |> to_string(),
      "user_id" => if(set.user_id, do: set.user_id |> to_string(), else: nil),
      "exercise" => set.exercise,
      "measure" => set.measure,
      "amount" => set.amount,
      "load_kind" => set.load_kind,
      "load_value" => set.load_value,
      "date" => set.date |> to_string(),
      "created_at" => set.inserted_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601(),
      "updated_at" => set.updated_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601()
    }
  end
end

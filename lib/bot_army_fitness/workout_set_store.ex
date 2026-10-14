defmodule BotArmyFitness.WorkoutSetStore do
  @moduledoc """
  Set storage: every read is a database read.

  The rule `WorkoutStore` learned the hard way, restated with what is actually
  true: **air and mini each run this bot against its own `ergon_fitness`
  database** — measured 2026-10-14: air's `workouts` held 1 row, mini's held 0,
  and ten `fitness.workout.list` requests on air's broker were answered by air
  every time. Where the two brokers meet the nodes do share one queue group, so a
  set can be written into the copy that the next read does not use. A process
  holding sets in memory would answer "this is what you lifted" from whichever
  node happened to be asked, and a wrong "last time" is wrong coaching rather than
  a missing one — so there is no cache here either, and a read that cannot reach
  the database fails instead of answering "no sets".

  (Mini's copy is a standby that starts empty and nothing keeps it in step; a
  failover to mini loses her training history until the data is copied over —
  `make migrate-live-db-to-mini BOT=fitness`.)

  ## Which set is "the newest one"

  Both reads order by **the day the set happened** and only then by when the row was
  written. A set is dated by the day it was performed, so an older day backfilled
  later must not become "last time", and `recent/2`'s newest row is the day the
  scheduler counts from. Ordering by insertion alone would let a backfilled row
  move both answers.

  ## API

  - `create/1` — store one set
  - `recent/2` — a tenant's sets, newest first (limit)
  - `for_exercise/3` — one movement's sets, newest first (limit)
  - `newest_per_exercise/2` — the newest set of each of several movements, in one read
  - `distinct_days/1` — the days she trained, one per day
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
     |> order_by([s], desc: s.date, desc: s.inserted_at)
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
     |> order_by([s], desc: s.date, desc: s.inserted_at)
     |> limit(^normalise_limit(limit))
     |> Repo.all()
     |> Enum.map(&schema_to_map/1)}
  end

  @doc """
  The newest set of each of several movements, in one read — `%{movement => [set]}`.

  The coach asks about a whole session at once (four to six slots, each offering several
  movements), and asking one query per movement would be twenty-odd round trips for a
  question the database can answer in one. `DISTINCT ON` needs the leftmost `ORDER BY`
  term to be the distinct expression, which is what pins the row that survives to the
  same one `for_exercise/3` would return: the newest day, then the newest row.

  A movement with no sets is simply absent from the map; the caller does not get an
  empty list for it, because "no sets" and "no movement" are the same answer here.
  """
  @impl true
  def newest_per_exercise(tenant_id, exercises)
      when is_binary(tenant_id) and is_list(exercises) do
    {:ok,
     WorkoutSet
     |> where([s], s.tenant_id == ^tenant_id and s.exercise in ^exercises)
     |> order_by([s], asc: s.exercise, desc: s.date, desc: s.inserted_at)
     |> distinct([s], s.exercise)
     |> Repo.all()
     |> Enum.map(&schema_to_map/1)
     |> Map.new(&{&1["exercise"], [&1]})}
  end

  @doc """
  The days she trained, as dates — one per day, however many sets that day held.

  The database counts the days rather than the caller counting rows, so the answer does
  not grow with her log. A day is a `date` column, which the store writes as the day the
  set happened (`Date.utc_today()` when the caller does not say), the same convention the
  scheduler counts from.
  """
  @impl true
  def distinct_days(tenant_id) when is_binary(tenant_id) do
    {:ok,
     WorkoutSet
     |> where([s], s.tenant_id == ^tenant_id)
     |> distinct([s], s.date)
     |> select([s], s.date)
     |> Repo.all()
     |> Enum.reject(&is_nil/1)}
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

defmodule BotArmyFitness.Handlers.SetListHandler do
  @moduledoc """
  Her recorded sets: `fitness.set.list`.

  The read a kept set never had. `fitness.set.record` stores a row and answers with it,
  but until this verb existed nothing in the fleet could ask for those rows back:
  `fitness.workout.list` answers with workouts, and a set is not one — it has no length
  and no hardness. So the only sight anyone got of a set was the answer to its own
  write, which the surface deliberately does not treat as a list.

  It reads through `WorkoutSetStore.recent/2` — the same store, the same tenant, the
  same `desc: date, desc: inserted_at` ordering that `fitness.set.record` writes into
  and that `Scheduler.days_since_last_workout/0` counts from. So the newest row here is
  the newest day she trained, and a backfilled older day cannot become it.

  ## A read that fails says so

  `fitness.workout.list` degrades a store error to an empty list, and a caller cannot
  tell that from "she has logged nothing" — which is the exact lie this house's cards
  are built to avoid. This verb does not repeat it: a store that cannot answer is
  `Reply.error/2` with `:read_failed`, so the card above it can say the log could not be
  read instead of drawing it empty.

  ## One list, no second question

  The request takes an optional `"limit"`, the same two-shape rule every fitness verb
  follows (`"payload"` for an envelope, the top level for a flat request/reply body),
  and answers `{"sets": […], "count": n, "limit": n}` — the same three keys
  `fitness.workout.list` answers with, so a surface that draws one list can draw the
  other. Nothing here re-derives what a set means: `exercise`, `measure`, `amount` and
  the load are the row's own fields, put there by the movement's catalog entry.

  There is deliberately no per-movement question here. "What did I lift last time on
  this movement" is `BotArmyFitness.Progression`'s, asked of the history a write already
  reads — a second subject for it would be a second way to ask one thing.
  """

  require Logger

  alias BotArmyFitness.WorkoutSetStore
  alias BotArmyLibraryRuntime.NATS.Reply

  @default_limit 10

  @doc """
  Answer a `fitness.set.list` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, the same shape `SetRecordHandler` and
  `WorkoutHandler.handle_options/1` answer with, so the consumer's clause is one line.
  """
  def handle_list(message) do
    %{tenant_id: tenant_id} = BotArmyLibraryCore.Tenant.extract_context(message)
    limit = limit(message)

    case read_sets(tenant_id, limit) do
      {:ok, sets} ->
        Reply.ok(%{"sets" => sets, "count" => length(sets), "limit" => limit})

      {:error, reason} ->
        Logger.warning("Could not read the sets: #{inspect(reason)}")
        Reply.error("the set log could not be read", :read_failed)
    end
  end

  # The store call is wrapped because a store that cannot answer must not take the
  # consumer process down with it: every fitness subscription rides on this one process,
  # so a raise here would stop answering `fitness.workout.list` too. And unlike
  # `fitness.workout.list`, the failure is not flattened into an empty list — see the
  # moduledoc.
  defp read_sets(tenant_id, limit) do
    case set_store().recent(tenant_id, limit) do
      {:ok, sets} when is_list(sets) -> {:ok, sets}
      other -> {:error, {:unexpected_store_reply, other}}
    end
  rescue
    e -> {:error, e}
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end

  # The request's fields are read with the same two-shape rule as the other fitness
  # verbs: an envelope leaves them under `"payload"`, and a flat request/reply body puts
  # them at the top level.
  defp limit(message) do
    payload = message["payload"] || message

    case Map.get(payload, "limit") do
      limit when is_integer(limit) and limit > 0 -> limit
      _absent_or_wrong -> @default_limit
    end
  end
end

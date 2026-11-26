defmodule BotArmyFitness.Handlers.SetDeleteHandler do
  @moduledoc """
  Take back one set: `fitness.set.delete`.

  The undo for the pocket's one-press set. The workout card records a set in a single
  press and answers with the row it wrote — `"set" => %{"id" => ...}` — so the press that
  takes it back names **that** id and nothing else. No "the last set", no "the newest set
  of this movement": a card whose undo guessed which row it meant would eventually take
  back a set she lifted last week.

  ## A set is taken back, not erased

  The store marks the row (`BotArmyFitness.WorkoutSetStore.delete/2`), and every read
  filters marked rows out. The consequence a caller can see is the one that matters: the
  movement's progression is whatever it was before the press, because "last time" and
  "next" are rebuilt from live rows.

  ## What it refuses, and in whose words

  An id that is not this tenant's answers `:not_found` with a sentence, never an empty
  success: a caller that could not take a set back must not be told it did. A request with
  no id answers `:missing_set` — the handler is not allowed to assume which set was meant,
  because assuming is exactly the bug this verb exists to avoid.

  Pressing undo twice answers fine: the second delete of an already-taken-back row is the
  same fact stated again, and a person who pressed twice has not made an error.
  """

  require Logger

  alias BotArmyFitness.{ExerciseCatalog, WorkoutSetStore}
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Handle a `fitness.set.delete` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, so the consumer's clause is one line.
  """
  def handle_delete(message) do
    %{tenant_id: tenant_id} = Tenant.extract_context(message)
    payload = message["payload"] || message

    case payload["id"] do
      id when is_binary(id) and id != "" ->
        delete(tenant_id, id)

      _missing ->
        Logger.warning("Refused set delete: no id in the request")
        Reply.error("no set was named", :missing_set)
    end
  rescue
    e ->
      Logger.warning("The set undo raised: #{inspect(e)}")
      Reply.error("the set could not be taken back", :read_failed)
  end

  defp delete(tenant_id, id) do
    case store().delete(tenant_id, id) do
      {:ok, set} ->
        Logger.info("Took back set #{id}: #{inspect(set["exercise"])}")

        Reply.ok(%{"set" => Map.put(set, "label", ExerciseCatalog.label(set["exercise"]))})

      {:error, :not_found} ->
        Reply.error("that set is not in your log", :not_found)

      {:error, reason} ->
        Logger.warning("Failed to take back set #{id}: #{inspect(reason)}")
        Reply.error("the set could not be taken back", :persist_failed)
    end
  end

  defp store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end
end

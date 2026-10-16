defmodule BotArmyFitness.Handlers.CoachTodayHandler do
  @moduledoc """
  Today's session: `fitness.coach.today`.

  The read the method needed. `BotArmyFitness.Coach` holds four sessions and the rule
  that turns them; this verb is the one place that gathers the two facts the rule reads —
  how many days she has trained, and the newest set of each movement a session offers —
  and answers with the session.

  ## Why this is a separate verb and not a better `fitness.workout.today`

  `fitness.workout.today` answers with a *type* ("strength, 30–60 min") derived from a
  hash of the user id and the day of the year, and it names no movement. It is a
  placeholder that predates the catalog. It is left in place — a surface still drawing it
  would break if it vanished — but **it is superseded**: this verb is the bot's answer to
  "what should I do today", and a caller that wants a programme wants this one. The
  difference is not that this one moves with the calendar (both do, now); it is that this
  one is the method's own session, filled with **her** numbers out of her log, where the
  old one is a type name chosen by a hash of who she is.

  ## A read that fails says so, and so does a missing day count

  Three things can go wrong, and all three answer `:read_failed` rather than a session:
  the day count could not be read, the day count is not a number (which is the same
  failure one step later), or the movement history could not be read. A coach that
  answered "Push A" because a database hiccup looked like a fresh log would be inventing
  a training decision, which is the one thing `Progression` and this module both refuse.

  ## What travels

  The day the answer is *for* travels on the rotation, because the card that draws it is
  labelled "today" and a label is a promise:

      {"length": 4, "position": 1, "days_trained": 5, "date": "2026-10-16"}

  `"date"` is the house's own day (`BotArmyFitness.HouseholdDay`), the same day the set
  log files a set under and the same day the rotation stands on, so a caller can print
  which day it is holding instead of assuming. `"position"` is that day's index in the
  rotation, and `"days_trained"` is the count of distinct days she has trained — a fact
  about her log that travels beside the session and decides nothing. The session itself
  carries the slots, and every slot carries each of its movements with **her** next
  number (`Progression`'s three answers, unchanged: a set-shaped map, `"top"`, or `null`)
  and the day she last did it. Nothing here re-derives a number, and nothing here chooses
  a movement for her: `"recent"` names the one she did most recently, and the rest stay on
  the wire beside it.
  """

  require Logger

  alias BotArmyFitness.{Coach, HouseholdDay, Scheduler, WorkoutSetStore}
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Answer a `fitness.coach.today` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, the shape `SetListHandler.handle_list/1`
  answers with, so the consumer's clause is one line.
  """
  def handle_today(message) do
    %{tenant_id: tenant_id} = Tenant.extract_context(message)

    # The day is read once, here, and every part of the answer is built from that one value:
    # read again beside each field, an answer that crossed midnight mid-flight could name one
    # day and the session of another.
    date = HouseholdDay.today()

    with {:ok, days} when is_integer(days) and days >= 0 <- days_trained(),
         session when is_map(session) <- Coach.owed_on(date),
         {:ok, history} <- history(tenant_id, session) do
      Reply.ok(%{
        "rotation" => %{
          "length" => Coach.session_count(),
          "position" => Coach.position(date),
          "days_trained" => days,
          "date" => Date.to_iso8601(date)
        },
        "session" => Coach.plan(session, history)
      })
    else
      # A read of the log that came back as something other than a count is the same
      # failure as a read that did not come back at all: the session no longer turns on
      # this number, but the card still says it, and a bot that answered a session with
      # "trained an unknown number of days" beside it would be answering half a fact as a
      # whole one.
      {:ok, not_a_count} ->
        Logger.warning(
          "The coach read a day count that is not a whole number of days: #{inspect(not_a_count)}"
        )

        Reply.error("the training log could not be read", :read_failed)

      other ->
        Logger.warning("The coach could not read the training log: #{inspect(other)}")
        Reply.error("the training log could not be read", :read_failed)
    end
  end

  # The day count and the history both come from stores, and both are wrapped: every
  # fitness subscription rides on one consumer process, so a raise here would stop
  # `fitness.set.list` answering too.
  defp days_trained do
    Scheduler.training_days()
  rescue
    e -> {:error, e}
  end

  defp history(tenant_id, session) do
    case set_store().newest_per_exercise(tenant_id, movements_in(session)) do
      {:ok, history} when is_map(history) -> {:ok, history}
      other -> {:error, {:unexpected_store_reply, other}}
    end
  rescue
    e -> {:error, e}
  end

  defp movements_in(session) do
    session["slots"]
    |> Enum.flat_map(& &1["options"])
    |> Enum.uniq()
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end
end

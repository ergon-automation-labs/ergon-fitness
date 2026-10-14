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
  placeholder that predates the catalog, and its answer changes when the calendar does
  and not when her training does. It is left in place — a surface still drawing it would
  break if it vanished — but **it is superseded**: this verb is the bot's answer to "what
  should I do today", and a caller that wants a programme wants this one.

  ## A read that fails says so, and so does a missing day count

  Three things can go wrong, and all three answer `:read_failed` rather than a session:
  the day count could not be read, the day count is not a number (which is the same
  failure one step later), or the movement history could not be read. A coach that
  answered "Push A" because a database hiccup looked like a fresh log would be inventing
  a training decision, which is the one thing `Progression` and this module both refuse.

  ## What travels

  The rotation's position travels beside the session, because "which one is this" is
  otherwise invisible: `{"length": 4, "position": 1, "days_trained": 5}` says she is owed
  the second session and has trained five days. The session itself carries the slots, and
  every slot carries each of its movements with **her** next number (`Progression`'s
  three answers, unchanged: a set-shaped map, `"top"`, or `null`) and the day she last did
  it. Nothing here re-derives a number, and nothing here chooses a movement for her:
  `"recent"` names the one she did most recently, and the rest stay on the wire beside it.
  """

  require Logger

  alias BotArmyFitness.{Coach, Scheduler, WorkoutSetStore}
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Answer a `fitness.coach.today` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, the shape `SetListHandler.handle_list/1`
  answers with, so the consumer's clause is one line.
  """
  def handle_today(message) do
    %{tenant_id: tenant_id} = Tenant.extract_context(message)

    with {:ok, days} <- days_trained(),
         session when is_map(session) <- Coach.owed(days),
         {:ok, history} <- history(tenant_id, session) do
      Reply.ok(%{
        "rotation" => %{
          "length" => Coach.session_count(),
          "position" => rem(days, Coach.session_count()),
          "days_trained" => days
        },
        "session" => Coach.plan(session, history)
      })
    else
      nil ->
        Logger.warning("The coach could not read how many days she has trained")
        Reply.error("the training log could not be read", :read_failed)

      {:error, reason} ->
        Logger.warning("The coach could not read the training log: #{inspect(reason)}")
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

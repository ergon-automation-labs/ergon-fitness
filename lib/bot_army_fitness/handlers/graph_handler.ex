defmodule BotArmyFitness.Handlers.GraphHandler do
  @moduledoc """
  The graphs her log can draw: `fitness.graph.series`.

  One read for the whole menu rather than one subject per chart. A card that offers a
  list of graphs needs to know what the list *is* before anybody picks one, and a dozen
  subjects would be a dozen ways to ask one question ("what could you draw?") — so the
  bot answers with every series it knows, each carrying its own points, and the page
  chooses which one to show. `Graphs` owns what a series means; this module owns only the
  reading, and it reads the same three stores the rest of this bot reads.

  ## A read that fails says so

  Three reads go into this answer and any one of them failing is a refusal with
  `:read_failed` rather than a shorter menu. A graph drawn from a store that did not
  answer would be a *wrong* graph — an empty week that had sets in it — and a wrong chart
  is worse than a missing one, because nothing about it looks broken. The page says the
  log could not be read instead.

  ## Bounded by the window the labels describe

  The sets read starts at `Graphs.window_days/0` before today, which is exactly the span
  `Graphs.week_buckets/2` names. So the numbers cannot grow with the log and the labels
  cannot describe a window the data came from somewhere else in.
  """

  require Logger

  alias BotArmyFitness.CardioSessionStore
  alias BotArmyFitness.Graphs
  alias BotArmyFitness.HouseholdDay
  alias BotArmyFitness.WorkoutSetStore
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Answer a `fitness.graph.series` request. Always answers, never raises.

  Returns the same already-encoded `Reply` binary every other read on this bot answers
  with, so the consumer's clause is one line.
  """
  def handle_graphs(message) do
    %{tenant_id: tenant_id} = BotArmyLibraryCore.Tenant.extract_context(message)
    today = HouseholdDay.today()
    since = Date.add(today, -Graphs.window_days())

    case read_log(tenant_id, since) do
      {:ok, data} ->
        graphs = Graphs.build(data, today)

        Reply.ok(%{
          "graphs" => graphs,
          "count" => length(graphs),
          "window_days" => Graphs.window_days()
        })

      {:error, reason} ->
        Logger.warning("Could not read the log to draw the graphs: #{inspect(reason)}")

        Reply.error(
          "The log could not be read just now, so nothing can be drawn from it.",
          :read_failed
        )
    end
  end

  # The three reads the menu is made of. `distinct_days/1` is the database's own count of
  # her training days rather than a count of rows, so a day with six sets is one day —
  # the same number `Scheduler.days_since_last_workout/0` reads.
  defp read_log(tenant_id, since) do
    with {:ok, dates} <- call(set_store(), :distinct_days, [tenant_id]),
         {:ok, sets} <- call(set_store(), :since, [tenant_id, since]),
         {:ok, cardio} <- call(cardio_store(), :list_recent, [tenant_id, Graphs.window_days()]) do
      {:ok, %{dates: dates, sets: sets, cardio: cardio}}
    end
  end

  defp call(module, function, args) do
    case apply(module, function, args) do
      {:ok, value} when is_list(value) -> {:ok, value}
      other -> {:error, {:unexpected_store_reply, other}}
    end
  rescue
    error -> {:error, error}
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end

  defp cardio_store do
    Application.get_env(:bot_army_fitness, :cardio_session_store, CardioSessionStore)
  end
end

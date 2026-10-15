defmodule BotArmyFitness.Handlers.CoachLastHandler do
  @moduledoc """
  Her last session again: `fitness.coach.last`.

  The read behind "do the last session again". It answers one question about her log —
  which day she trained most recently, and which movements she did that day — and nothing
  else, so the surface above it never has to decide for itself what counts as a session.

  ## Why the bot answers this and not the page

  Grouping a list of sets into "one session" is the bot's vocabulary, the same rule §59
  settled for muscle groups: a page that picked the newest date out of a page of rows
  would be choosing where a session begins, and would cut the newest one in half whenever
  the page ended in the middle of it. The store finds the day with its own date-first
  ordering and reads only that day's rows, so the answer is whole however long the log is.

  ## A fact, not a plan

  Nothing here chooses anything and nothing here is added on the method's behalf. The
  movements are read back in the order she last touched them; each carries the newest set
  of that movement that day — the measure, the amount and the load exactly as the row
  holds them. A surface may draw that number as context, but the number that keeps a set
  is still the one she presses (`fitness.set.record`), so this read stages nothing.

  ## An empty log is a fact; a failed read is a refusal

  `{"day": null, "movements": [], "count": 0}` is what a tenant with no sets gets back:
  she has not trained yet, and that is an answer. A store that cannot be read is
  `Reply.error/2` with `:read_failed` instead, because drawing the two the same way would
  make "the log could not be read" look like "there is nothing to repeat".
  """

  require Logger

  alias BotArmyFitness.WorkoutSetStore
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Answer a `fitness.coach.last` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, the same shape `CoachTodayHandler` answers
  with, so the consumer's clause is one line.
  """
  def handle_last(message) do
    %{tenant_id: tenant_id} = Tenant.extract_context(message)

    case read_last_day(tenant_id) do
      {:ok, nil} ->
        Reply.ok(%{"day" => nil, "movements" => [], "count" => 0})

      {:ok, %{"date" => day, "sets" => sets}} ->
        movements = movements(sets)
        Reply.ok(%{"day" => day, "movements" => movements, "count" => length(movements)})

      {:error, reason} ->
        Logger.warning("Could not read her last session: #{inspect(reason)}")
        Reply.error("the training log could not be read", :read_failed)
    end
  end

  # Wrapped like every other store read in this bot: every fitness subscription rides on
  # one consumer process, so a raise here would stop the other reads answering too.
  defp read_last_day(tenant_id) do
    case set_store().recent_day(tenant_id) do
      {:ok, nil} -> {:ok, nil}
      {:ok, %{"date" => _day, "sets" => sets} = day} when is_list(sets) -> {:ok, day}
      other -> {:error, {:unexpected_store_reply, other}}
    end
  rescue
    e -> {:error, e}
  end

  # One entry per movement, in the order she last touched them. The sets arrive newest
  # first, so the first row seen for a movement is the last set she did of it that day —
  # a fact about the log, with no rule of the coach's on top.
  defp movements(sets) do
    sets
    |> Enum.uniq_by(& &1["exercise"])
    |> Enum.map(&movement/1)
  end

  defp movement(set) do
    %{
      "value" => set["exercise"],
      "measure" => set["measure"],
      "amount" => set["amount"],
      "load_kind" => set["load_kind"],
      "load_value" => set["load_value"]
    }
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end
end

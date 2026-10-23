defmodule BotArmyFitness.Progression do
  @moduledoc """
  What to reach for next — the one progression rule this gym has, and it is double
  progression.

  `ExerciseCatalog` is a menu: the equipment, the movements, and the range each movement
  counts in. It holds no rule about *how* anybody gets stronger, because a menu that
  ranked its own items would be a curriculum. This module is the rule.

  **The count moves first, and the load moves only when the count has topped out.**

    * the count climbs through the movement's own window — `ExerciseCatalog`'s `"min"`
      and `"max"`, walked in `ExerciseCatalog.rep_choices/0`'s steps
    * at the top of that window, the piece goes up one rung of *its own* ladder and the
      count drops back to the bottom of the window
    * a bodyweight movement has no ladder to climb, so at the top of its window there is
      nothing higher to reach for

  Nothing here reads a clock, a streak, or a session count. A set she did a month ago and
  one she did an hour ago are the same input: the newest set is the whole of it.

  ## Why a pure function over a list

  `next_load/1` takes one movement's sets, newest first — the shape
  `WorkoutSetStore.for_exercise/3` answers with, and the shape a log holds. It reads the
  newest one. It takes the history rather than that single row because that is the shape
  the question has: a rule that later needs the set *before* the newest — a deload, a
  stall — must not move every caller's arity, and every caller already holds the list.

  ## The three answers

    * a **set-shaped map** — the set to aim at, carrying the same keys a stored row
      carries (`"exercise"`, `"measure"`, `"amount"`, `"load_kind"`, `"load_value"`), so
      the one function that draws a set row draws this too
    * `"top"` — the count is at the top of the window and this piece has no higher
      number. A real fact, and one worth saying out loud rather than rounding into a
      heavier suggestion the equipment cannot make
    * `nil` — this rule does not answer here. Silence covers: no sets at all; a movement
      outside this house's gym; a movement that counts `"seconds"`, because a hold
      progresses in time and the step for adding time is the surface's rule and not this
      one's; a count that is not a whole positive number; a window with no choice inside
      it; and a laddered piece whose set carries no load — there *is* a rung above her
      there, and this rule does not know which one she is standing on. Every one of those
      is a place a guess would be this bot inventing a training decision

  A `nil` `"load_value"` on the way out is not an omission: for a bodyweight movement the
  body *is* the load, so the target's number is absent and only its count moves.
  """

  alias BotArmyFitness.ExerciseCatalog

  @reps "reps"
  @top "top"

  # The same tolerance `ExerciseCatalog.load_allowed?/2` reads a stored float back onto
  # its ladder with: a setting that differs from a rung by a rounding error is that rung,
  # and must not be read as a rung of its own.
  @tolerance 0.01

  # A step ladder is walked upward until it stops, so the walk needs its own ceiling in
  # case a piece is ever seeded with a step and no top. No device in the catalog is.
  @max_rungs 100

  @doc """
  The set to reach for next, from one movement's history.

  `sets` is that movement's sets, newest first; only the first is read. See the moduledoc
  for the rule and for what the three answers mean.
  """
  @spec next_load(term()) :: map() | String.t() | nil
  def next_load([set | _rest]) when is_map(set) do
    case counted_movement(set) do
      {:ok, movement} -> advance(movement, set)
      :error -> nil
    end
  end

  def next_load(_sets), do: nil

  # A movement whose range counts reps, and this house's movement at all. A hold
  # (`"seconds"`) is not this rule's business: the count that moves is a count of reps.
  defp counted_movement(%{"exercise" => value}) when is_binary(value) do
    case ExerciseCatalog.exercise(value) do
      %{"measure" => @reps} = movement -> {:ok, movement}
      _other -> :error
    end
  end

  defp counted_movement(_set), do: :error

  defp advance(movement, set) do
    case count(set["amount"]) do
      {:ok, amount} -> walk(movement, window(movement), amount, set)
      :error -> nil
    end
  end

  # The window, in the order the count should walk it: the counts this movement lets her
  # press, that fall inside its range. A movement with its own counts walks those — a
  # pull-up logged at 1 answers "2", not the house list's "5" — and one without them
  # walks the house list. A range with no count inside it — a window narrower than the
  # coarsest step between counts — cannot be walked, so the rule stays silent.
  defp window(movement) do
    min = movement["min"]
    max = movement["max"]

    ExerciseCatalog.counts_for(movement)
    |> List.wrap()
    |> Enum.filter(&(&1 >= min and &1 <= max))
  end

  defp walk(_movement, [], _amount, _set), do: nil

  defp walk(movement, window, amount, set) do
    if amount < List.last(window) do
      set
      |> target()
      |> Map.put("amount", Enum.find(window, &(&1 > amount)))
    else
      climb(movement, window, set)
    end
  end

  # The count has topped out. One rung up the piece's own ladder, and the count back to
  # the bottom of the window — or `"top"`, when the piece has no rung above where she is.
  defp climb(movement, window, set) do
    case rung_above(movement, set) do
      {:ok, value} ->
        set
        |> target()
        |> Map.merge(%{"amount" => hd(window), "load_value" => value})

      :exhausted ->
        @top

      :unknown ->
        nil
    end
  end

  # The next rung of the piece's own ladder, or why there is none to name.
  #
  # `:exhausted` — there is no rung above her: the ladder stops where she is (the
  # dumbbells at 55, the clutch at 25, the kettlebell at 44), or the piece is bodyweight
  # and so has no ladder at all (`ExerciseCatalog.load_settings/1` answers `nil` for the
  # body, and inventing one would be inventing a weight).
  #
  # `:unknown` — the piece *has* a ladder and the set does not say where on it she is, so
  # neither rung is right and the rule stays silent rather than guessing at the bottom.
  defp rung_above(movement, set) do
    case ExerciseCatalog.load_settings(movement["equipment"]) do
      nil ->
        :exhausted

      %{} = ladder ->
        case number(set["load_value"]) do
          {:ok, current} -> next_rung(ladder, current)
          :error -> :unknown
        end
    end
  end

  defp next_rung(ladder, current) do
    case Enum.find(rungs(ladder), &(&1 > current + @tolerance)) do
      nil -> :exhausted
      value -> {:ok, value}
    end
  end

  # The ladder as the values it actually offers: an explicit list for the kettlebell, and
  # a step up to the top for the dumbbells and the MaxPRO.
  defp rungs(%{"settings" => settings}) when is_list(settings), do: settings

  defp rungs(%{"min" => min, "step" => step} = ladder) when is_number(min) and is_number(step) do
    stop =
      case ladder["max"] do
        max when is_number(max) -> max + @tolerance
        _absent -> nil
      end

    walk_rungs(min, step, stop, [])
  end

  defp rungs(_ladder), do: []

  # The rungs are walked rather than generated so that a ladder with no top stops at
  # `@max_rungs` instead of running forever: a step of zero or less would otherwise be an
  # endless ladder, and a menu is not a place to hang the consumer.
  defp walk_rungs(_value, _step, _stop, acc) when length(acc) >= @max_rungs, do: Enum.reverse(acc)

  defp walk_rungs(value, step, stop, acc) do
    if is_number(stop) and value > stop do
      Enum.reverse(acc)
    else
      walk_rungs(value + step, step, stop, [value | acc])
    end
  end

  # A whole positive count. This is the reader `SetRecordHandler` already puts `amount`
  # through, so a stored row cannot fail here — and a row that never got past it must not
  # be progressed.
  defp count(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp count(value) when is_float(value) do
    if value == Float.round(value) and value > 0, do: {:ok, trunc(value)}, else: :error
  end

  defp count(_value), do: :error

  # A load, which is a measurement and not a count: `24.5` is a weight on the kettlebell's
  # ladder, so it may not be truncated the way a rep count may.
  defp number(value) when is_number(value) and value > 0, do: {:ok, value}
  defp number(_value), do: :error

  # The suggestion carries the row's own words and nothing that belongs to a row that
  # happened: no id, no tenant, and above all no date. A suggestion dated is a set she did
  # not do.
  defp target(set),
    do: Map.take(set, ["exercise", "measure", "amount", "load_kind", "load_value"])
end

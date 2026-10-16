defmodule BotArmyFitness.Graphs do
  @moduledoc """
  The graphs this bot can draw from her log: the menu, and the numbers behind it.

  A graph is a question about her log with a shape attached, and both halves of that
  belong to this bot rather than to the page that draws it. Which weeks a series covers,
  what one bar counts, and what a number means on the piece it came from are facts about
  *this gym*; the page's job is to turn a list of points into a path and print the words
  it was handed. Nothing here knows about pixels, and nothing on the page knows what a
  week is.

  ## Every series is always here, drawn or not

  This answers with the whole menu every time, including the series her log cannot fill
  yet, each carrying its own points — an empty list is a fact the page can say out loud
  ("nothing kept yet"), and a series that vanished until it had data would be a graph
  she could only discover by accident. The page picks one to show; the menu is this
  bot's.

  ## What is deliberately *not* here

  There is no chart comparing movements. The loads in this house are **per piece and are
  never normalised**: the MaxPRO is a resistance level out of 25, the dumbbells and the
  kettlebell are kilograms on their own uneven ladders, and the bars are the body. A bar
  chart of "heaviest lift" across movements would draw a level 18 beside 24.5 kg beside a
  pull-up and invite exactly the comparison this house refuses to make — a level is not a
  smaller kilogram, it is a different unit. So a load is only ever plotted *against itself,
  over time, on one movement*, and the series says which unit it is in.

  ## Why the bucketing lives here

  `week_buckets/2` starts a week on Monday and counts twelve of them back from today, the
  same convention `HouseholdDay` gives the rest of this bot, and a page that bucketed for
  itself would eventually disagree with this module about which day a set landed in.
  """

  alias BotArmyFitness.ExerciseCatalog

  @weeks 12

  @doc """
  How many days of log a graph is built from — the twelve weeks `week_buckets/2` names.

  The handler reads exactly this window, so a graph cannot quietly mean a different
  window than the one its labels describe.
  """
  @spec window_days() :: pos_integer()
  def window_days, do: @weeks * 7

  @doc """
  The weeks a series is drawn over, oldest first — Monday-started, ending with the week
  today is in.

  The label is the Monday, because an unlabelled axis is a chart nobody can read and a
  label on every bar is a chart nobody can read either; the page prints the first and the
  last and leaves the rest off.
  """
  @spec week_buckets(Date.t(), pos_integer()) :: [%{start: Date.t(), label: String.t()}]
  def week_buckets(today, count \\ @weeks) do
    this_monday = Date.add(today, -(Date.day_of_week(today, :monday) - 1))

    for i <- 0..(count - 1) do
      start = Date.add(this_monday, -(count - 1 - i) * 7)
      %{start: start, label: Calendar.strftime(start, "%b %-d")}
    end
  end

  @doc """
  Build every series, in the order they are offered.

  `data` is what the handler read: `:dates` (her training days), `:sets` (the sets kept
  inside the window) and `:cardio` (the cardio sessions inside it). Anything missing is
  read as "none", which is the same answer this module gives for a log with nothing in
  it — the caller does not have to spell out the empty case.

  Every series is a `%{"id", "title", "unit", "kind", "note", "points"}` map. `"kind"` is
  `"bars"` when each point stands alone (a count per week) and `"line"` when the points
  are a path through time; that is a fact about the numbers rather than a style, which is
  why it is chosen here.
  """
  @spec build(map(), Date.t()) :: [map()]
  def build(data, %Date{} = today) when is_map(data) do
    weeks = week_buckets(today, @weeks)

    [
      days_trained(data, weeks),
      sets_kept(data, weeks),
      heaviest_load(data),
      cardio(data, weeks, "miles"),
      cardio(data, weeks, "minutes")
    ]
  end

  # ── the series ────────────────────────────────────────────────────────────────

  defp days_trained(data, weeks) do
    counts = count_weeks(dates(data, :dates), weeks)

    series(
      "fitness.sessions.week",
      "Days trained",
      "days",
      "bars",
      "each bar is one week, the last twelve",
      points(weeks, counts)
    )
  end

  defp sets_kept(data, weeks) do
    counts = count_weeks(dates(data, :sets), weeks)

    series(
      "fitness.sets.week",
      "Sets kept",
      "sets",
      "bars",
      "each bar is one week, the last twelve",
      points(weeks, counts)
    )
  end

  defp heaviest_load(data) do
    case busiest_exercise(Map.get(data, :sets, [])) do
      nil ->
        series(
          "fitness.loads.trend",
          "The heaviest number",
          nil,
          "line",
          "one point per day you trained a movement, its heaviest number that day — nothing kept yet",
          []
        )

      {exercise, sets} ->
        {unit, _measure} = unit_and_measure(exercise)

        series(
          "fitness.loads.trend",
          "The heaviest number — #{movement_label(exercise)}",
          unit,
          "line",
          "one point per day you trained it — the number that piece itself shows, never compared with another",
          heaviest_by_day(sets)
        )
    end
  end

  defp cardio(data, weeks, which) do
    sessions = Map.get(data, :cardio, [])

    {id, title, unit} =
      case which do
        "miles" -> {"fitness.cardio.miles.week", "Cardio, miles", "miles"}
        "minutes" -> {"fitness.cardio.minutes.week", "Cardio, minutes", "minutes"}
      end

    counts =
      Enum.reduce(sessions, List.duplicate(0, length(weeks)), fn session, acc ->
        case bucket_index(session_date(session), weeks, 7) do
          nil -> acc
          index -> List.update_at(acc, index, &(&1 + amount_of(session, which)))
        end
      end)
      |> Enum.map(&round_value/1)

    series(
      id,
      title,
      unit,
      "bars",
      "each bar is one week, the last twelve",
      points(weeks, counts)
    )
  end

  # ── the numbers ───────────────────────────────────────────────────────────────

  # The movement with the most sets in the window: the one a "how has my load moved"
  # question has an answer about. A tie is settled by the newest set, so the movement she
  # is actually training wins over an old one with the same number of rows.
  defp busiest_exercise(sets) do
    sets
    |> Enum.group_by(& &1["exercise"])
    |> Enum.reject(fn {exercise, rows} -> is_nil(exercise) or rows == [] end)
    |> Enum.map(fn {exercise, rows} -> {exercise, rows, newest(rows)} end)
    |> Enum.sort_by(fn {_e, rows, newest} -> {length(rows), newest} end, :desc)
    |> case do
      [] -> nil
      [{exercise, rows, _newest} | _rest] -> {exercise, rows}
    end
  end

  # One point per day: the heaviest number she kept on that day. A day can hold several
  # sets and a graph of all of them would draw a sawtooth nobody pressed.
  defp heaviest_by_day(sets) do
    sets
    |> Enum.group_by(&date_of/1)
    |> Enum.reject(fn {date, _rows} -> is_nil(date) end)
    |> Enum.map(fn {date, rows} -> {date, heaviest(rows)} end)
    |> Enum.reject(fn {_date, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {date, _value} -> date end, Date)
    |> Enum.map(fn {date, value} ->
      %{"label" => Calendar.strftime(date, "%b %-d"), "value" => round_value(value)}
    end)
  end

  # The load when the piece carries a number, and the count when it does not: a pull-up
  # has no weight to climb, so what moves there is the reps. One rule, either way, and the
  # series says which one it is in.
  defp heaviest(rows) do
    loads = rows |> Enum.map(& &1["load_value"]) |> Enum.reject(&is_nil/1)

    case loads do
      [] -> rows |> Enum.map(&amount_of(&1, "reps")) |> max_or_nil()
      loads -> Enum.max(loads)
    end
  end

  defp max_or_nil([]), do: nil
  defp max_or_nil(values), do: Enum.max(values)

  # The unit is the piece's own, and the words beside it are the movement's own measure.
  # A laddered piece answers with what its display shows (`kg`, `level`); a bodyweight
  # movement answers with what its count counts.
  defp unit_and_measure(exercise) do
    case ExerciseCatalog.exercise(exercise) do
      nil ->
        {nil, "reps"}

      %{"equipment" => equipment, "measure" => measure} ->
        case ExerciseCatalog.load_kind(equipment) do
          "kg" -> {"kg", measure}
          "level" -> {"level", measure}
          _other -> {measure, measure}
        end
    end
  end

  defp movement_label(exercise) do
    case ExerciseCatalog.exercise(exercise) do
      %{"label" => label} -> label
      _other -> to_string(exercise)
    end
  end

  defp amount_of(map, "miles"), do: number(Map.get(map, "distance_miles"))
  defp amount_of(map, "minutes"), do: number(Map.get(map, "duration_minutes"))
  defp amount_of(map, "reps"), do: number(Map.get(map, "amount"))
  defp amount_of(map, key), do: number(Map.get(map, key))

  defp number(value) when is_integer(value), do: value
  defp number(value) when is_float(value), do: value
  defp number(_other), do: 0

  # Dates off a row: a set carries `"date"`, a cardio session `"session_date"`.
  defp dates(data, :dates), do: Map.get(data, :dates, [])

  defp dates(data, :sets) do
    data |> Map.get(:sets, []) |> Enum.map(&date_of/1) |> Enum.reject(&is_nil/1)
  end

  defp date_of(row) do
    case Map.get(row, "date") do
      nil -> nil
      value when is_binary(value) -> parse_date(value)
      %Date{} = date -> date
      _other -> nil
    end
  end

  defp session_date(row) do
    case Map.get(row, "session_date") do
      nil -> nil
      value when is_binary(value) -> parse_date(value)
      %Date{} = date -> date
      _other -> nil
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _other -> nil
    end
  end

  defp newest(rows) do
    rows |> Enum.map(&date_of/1) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> ~D[1970-01-01] end)
  end

  # ── buckets ───────────────────────────────────────────────────────────────────

  defp count_weeks(dates, buckets) do
    Enum.reduce(dates, List.duplicate(0, length(buckets)), fn date, acc ->
      case bucket_index(date, buckets, 7) do
        nil -> acc
        index -> List.update_at(acc, index, &(&1 + 1))
      end
    end)
  end

  # Which bucket a date falls in, or nil for a date outside the window. Weeks are a
  # fixed stride from the first bucket, so the arithmetic is one division — and the bound
  # is the *count*, not the last bucket's start: a date later in the current week is
  # inside the last bucket, and comparing it against that bucket's Monday dropped every
  # set she kept today. `Integer.floor_div/2` rather than `div/2` for a date before the
  # window, whose negative offset `div/2` would round up to bucket zero.
  defp bucket_index(%Date{} = date, buckets, step_days) do
    index = Integer.floor_div(Date.diff(date, hd(buckets).start), step_days)

    if index >= 0 and index < length(buckets), do: index, else: nil
  end

  defp points(buckets, counts) do
    buckets
    |> Enum.zip(counts)
    |> Enum.map(fn {bucket, value} -> %{"label" => bucket.label, "value" => value} end)
  end

  defp series(id, title, unit, kind, note, points) do
    %{
      "id" => id,
      "title" => title,
      "unit" => unit,
      "kind" => kind,
      "note" => note,
      "points" => points
    }
  end

  defp round_value(value) when is_float(value), do: Float.round(value, 1)
  defp round_value(value), do: value
end

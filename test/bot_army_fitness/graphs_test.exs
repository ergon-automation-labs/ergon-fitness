defmodule BotArmyFitness.GraphsTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.Graphs

  # A day in the middle of a week, so "the week today is in" has days on both sides of it
  # and a bucket that dropped the future half of the current week would be caught.
  @today ~D[2026-10-16]

  describe "week_buckets/2" do
    test "ends on the Monday of the week today is in, and counts back in sevens" do
      buckets = Graphs.week_buckets(@today, 3)

      assert Enum.map(buckets, & &1.start) == [~D[2026-09-28], ~D[2026-10-05], ~D[2026-10-12]]
      assert Enum.map(buckets, & &1.label) == ["Sep 28", "Oct 5", "Oct 12"]
    end

    test "is Monday-started even when today is a Monday" do
      assert [_, last] = Graphs.week_buckets(~D[2026-10-12], 2)
      assert last.start == ~D[2026-10-12]
    end
  end

  describe "build/2" do
    test "offers every series, including the ones her log cannot fill" do
      graphs = Graphs.build(%{}, @today)

      assert Enum.map(graphs, & &1["id"]) == [
               "fitness.sessions.week",
               "fitness.sets.week",
               "fitness.loads.trend",
               "fitness.cardio.miles.week",
               "fitness.cardio.minutes.week"
             ]

      for graph <- graphs do
        assert is_list(graph["points"])
        assert graph["kind"] in ["bars", "line"]
        assert is_binary(graph["title"])
        assert is_binary(graph["note"])
      end

      # Every series carries points except the load trend, which carries none until there
      # is a movement to draw: an empty list of points under a title naming a movement
      # would be a chart of a lift she never did.
      [trend] = Enum.reject(graphs, &(&1["id"] != "fitness.loads.trend"))
      assert trend["points"] == []
      assert Enum.all?(graphs -- [trend], &(&1["points"] != []))
    end

    test "an empty log draws twelve empty weeks rather than nothing" do
      graphs = Graphs.build(%{}, @today)
      sessions = Enum.find(graphs, &(&1["id"] == "fitness.sessions.week"))

      assert length(sessions["points"]) == 12
      assert Enum.all?(sessions["points"], &(&1["value"] == 0))
    end

    test "counts the days she trained into the week each one belongs to" do
      data = %{dates: [~D[2026-10-16], ~D[2026-10-15], ~D[2026-09-28], ~D[2026-07-20]]}
      sessions = graphs(data)["fitness.sessions.week"]

      # The window is the twelve weeks from Mon 2026-07-27: 09-28 is the tenth bucket, the
      # two days this week are the twelfth, all empty weeks between are zeros, and the day
      # in July is older than the window and is dropped rather than folded into the first
      # bar — a bar for a week she did not train in would be a lie about that week.
      assert values(sessions) == [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2]
    end

    test "counts today's sets, which are inside the current week" do
      data = %{sets: [set("2026-10-16", "cable_row", 20.0)]}
      assert List.last(values(graphs(data)["fitness.sets.week"])) == 1
    end

    test "counts a set that lands on the first bucket's own Monday" do
      data = %{sets: [set("2026-07-27", "cable_row", 20.0)]}
      assert List.first(values(graphs(data)["fitness.sets.week"])) == 1
    end

    test "drops a set older than the window instead of folding it into the oldest bar" do
      data = %{sets: [set("2026-07-26", "cable_row", 20.0)]}
      assert Enum.all?(values(graphs(data)["fitness.sets.week"]), &(&1 == 0))
    end
  end

  describe "the load trend" do
    test "is one point per day, taking the heaviest number of that day" do
      data = %{
        sets: [
          set("2026-10-15", "cable_row", 20.0),
          set("2026-10-15", "cable_row", 22.5),
          set("2026-10-01", "cable_row", 18.0)
        ]
      }

      trend = graphs(data)["fitness.loads.trend"]

      assert trend["points"] == [
               %{"label" => "Oct 1", "value" => 18.0},
               %{"label" => "Oct 15", "value" => 22.5}
             ]
    end

    test "names the busiest movement and carries that piece's own unit" do
      data = %{
        sets: [
          set("2026-10-15", "cable_row", 20.0),
          set("2026-10-14", "cable_row", 20.0),
          set("2026-10-13", "goblet_squat", 16.0)
        ]
      }

      trend = graphs(data)["fitness.loads.trend"]

      # `cable_row` is a MaxPRO movement, so its number is a level and not a kilogram —
      # the one place this bot could have invented a comparison, and does not.
      assert trend["unit"] == "level"

      assert trend["title"] ==
               "The heaviest number — " <> ExerciseCatalog.exercise("cable_row")["label"]
    end

    test "plots the count for a bodyweight movement, because the body is the load" do
      data = %{
        sets: [
          bodyweight_set("2026-10-15", "pull_up", 8),
          bodyweight_set("2026-10-10", "pull_up", 6)
        ]
      }

      trend = graphs(data)["fitness.loads.trend"]

      assert trend["unit"] == "reps"
      assert values(trend) == [6, 8]
    end
  end

  describe "the cardio series" do
    test "sums miles and minutes into their own weeks" do
      data = %{
        cardio: [
          %{"session_date" => "2026-10-14", "distance_miles" => 2.5, "duration_minutes" => 30},
          %{"session_date" => "2026-10-13", "distance_miles" => 1.25, "duration_minutes" => 20}
        ]
      }

      assert List.last(values(graphs(data)["fitness.cardio.miles.week"])) == 3.8
      assert List.last(values(graphs(data)["fitness.cardio.minutes.week"])) == 50
    end
  end

  defp graphs(data), do: Map.new(Graphs.build(data, @today), &{&1["id"], &1})
  defp values(series), do: Enum.map(series["points"], & &1["value"])

  defp set(date, exercise, load) do
    %{
      "date" => date,
      "exercise" => exercise,
      "amount" => 10,
      "load_kind" => "kg",
      "load_value" => load
    }
  end

  defp bodyweight_set(date, exercise, reps) do
    %{
      "date" => date,
      "exercise" => exercise,
      "amount" => reps,
      "load_kind" => "bodyweight",
      "load_value" => nil
    }
  end
end

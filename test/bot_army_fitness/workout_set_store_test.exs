defmodule BotArmyFitness.WorkoutSetStoreTest do
  use ExUnit.Case
  @moduletag :stores

  alias BotArmyFitness.WorkoutSetStore

  @tenant "00000000-0000-0000-0000-000000000002"

  describe "the store keeps no rows of its own" do
    # Same rule as WorkoutStore, for the same reason: air and mini each run this bot
    # against its **own** `ergon_fitness` database (measured 2026-10-14: air held 1
    # workout, mini held 0, and ten `fitness.workout.list` requests on air's broker
    # were answered by air every time), and where their brokers meet the two nodes
    # share one queue group. A process holding sets in memory would answer "what did
    # she lift last time" with whatever that node happened to see, and a set written
    # into the other copy would be invisible — which is a wrong "last time" line,
    # i.e. wrong coaching advice rather than a missing one.
    test "it is a module, not a GenServer with a per-node cache" do
      Code.ensure_loaded(WorkoutSetStore)

      refute function_exported?(WorkoutSetStore, :start_link, 1),
             """
             WorkoutSetStore is a GenServer again. With two nodes writing to one
             database its in-memory map is a partial view: a set recorded on air is
             missing from `recent/2` on mini, so "last time" is a coin flip.
             """

      assert function_exported?(WorkoutSetStore, :create, 1)
      assert function_exported?(WorkoutSetStore, :recent, 2)
      assert function_exported?(WorkoutSetStore, :for_exercise, 3)
      assert function_exported?(WorkoutSetStore, :previous_for_exercise, 2)
    end
  end

  describe "the newest set is the newest day, not the newest insert" do
    # A lint, not a behaviour proof, and it says so: this suite has no database
    # (config/test.exs keeps the Repo out of the supervision tree), so the ordering
    # cannot be observed here. Both reads have to be date-first, because a set is
    # dated by the day it was performed: a backfilled older day must not become "last
    # time", and `recent/2`'s first row is the day `Scheduler.days_since_last_workout/0`
    # counts from. Comments are stripped first — this file's own prose says the words.
    test "both reads order by the set's day before the row's timestamp" do
      source =
        "lib/bot_army_fitness/workout_set_store.ex"
        |> File.read!()
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
        |> Enum.join("\n")

      assert String.contains?(source, "order_by([s], desc: s.date, desc: s.inserted_at)"),
             """
             a read in WorkoutSetStore orders by inserted_at alone. Then a set she
             backfills for an older day becomes "last time" and the scheduler counts
             from the day she typed it in, not the day she trained.
             """

      assert length(String.split(source, "order_by([s], desc: s.date, desc: s.inserted_at)")) ==
               3,
             "expected both reads (recent/2 and for_exercise/3) to be date-ordered"
    end
  end

  describe "a read is a database read" do
    # This suite runs with no database at all (`config/test.exs` keeps the Repo out of
    # the supervision tree), and that is what makes this a guard: the read has to *ask*.
    # A store that answered `{:ok, []}` here would make "the database is unreachable"
    # indistinguishable from "she has never done this movement", and the second answer
    # is what a progression line would print as fact.
    test "recent/2 cannot answer without the database" do
      assert_raise RuntimeError, ~r/Ecto repo/, fn -> WorkoutSetStore.recent(@tenant) end
    end

    test "for_exercise/3 cannot answer without the database" do
      assert_raise RuntimeError, ~r/Ecto repo/, fn ->
        WorkoutSetStore.for_exercise(@tenant, "kb_swing")
      end
    end

    test "previous_for_exercise/2 cannot answer without the database" do
      assert_raise RuntimeError, ~r/Ecto repo/, fn ->
        WorkoutSetStore.previous_for_exercise(@tenant, "kb_swing")
      end
    end
  end
end

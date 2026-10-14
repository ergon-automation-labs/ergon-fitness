defmodule BotArmyFitness.WorkoutSetStoreTest do
  use ExUnit.Case
  @moduletag :stores

  alias BotArmyFitness.WorkoutSetStore

  @tenant "00000000-0000-0000-0000-000000000002"

  describe "the store keeps no rows of its own" do
    # Same rule as WorkoutStore, for the same reason: air and mini both run this bot
    # against **one** `ergon_fitness` database, and since they share a queue group each
    # verb is answered by exactly one of them. A process holding sets in memory would
    # answer "what did she lift last time" with whatever that node happened to see, and
    # a set recorded on the other node would be invisible — which is a wrong "last time"
    # line, i.e. wrong coaching advice rather than a missing one.
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

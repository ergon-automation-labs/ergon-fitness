defmodule BotArmyFitness.WorkoutStoreTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.WorkoutStore

  @tenant "00000000-0000-0000-0000-000000000002"

  describe "the store keeps no rows of its own" do
    # air and mini both run this bot against **one** `ergon_fitness` database.
    # A process holding the workouts in memory can only ever hold the subset the
    # node it lives on has seen, so on air+mini `list/1` answered a different
    # list depending on which node replied. That is why the store is not a
    # process any more.
    test "it is a module, not a GenServer with a per-node cache" do
      Code.ensure_loaded(WorkoutStore)

      refute function_exported?(WorkoutStore, :start_link, 1),
             """
             WorkoutStore is a GenServer again. With two nodes writing to one
             database, its in-memory map is a partial view: a workout created on
             the other node is missing from `list/1`, which is exactly the defect
             that made a logged workout invisible.
             """

      assert function_exported?(WorkoutStore, :list, 1)
      assert function_exported?(WorkoutStore, :list_by_date, 2)
      assert function_exported?(WorkoutStore, :get, 2)
    end
  end

  describe "a read is a database read" do
    # This suite runs with no database at all (`config/test.exs` keeps the Repo
    # out of the supervision tree), and that is what makes this a guard: the read
    # has to *ask*. The old cache-based store answered `{:ok, []}` here — the same
    # answer as an account with no workouts — so a read that could not see the
    # data looked exactly like a read that found none.
    #
    # If this suite is ever given a database, replace these with real reads and
    # writes (create a workout, then list it through a second node's view).
    test "list/1 cannot answer without the database" do
      assert_raise RuntimeError, ~r/Ecto repo/, fn -> WorkoutStore.list(@tenant) end
    end

    test "list_by_date/2 cannot answer without the database" do
      assert_raise RuntimeError, ~r/Ecto repo/, fn ->
        WorkoutStore.list_by_date(@tenant, "2026-10-12")
      end
    end

    test "a malformed date is refused before the database is consulted" do
      assert {:error, :invalid_date} = WorkoutStore.list_by_date(@tenant, "not-a-date")
    end
  end
end

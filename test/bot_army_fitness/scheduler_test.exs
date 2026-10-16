defmodule BotArmyFitness.SchedulerTest do
  use ExUnit.Case

  @moduletag :core

  import Mox

  alias BotArmyFitness.HouseholdDay
  alias BotArmyFitness.Scheduler

  setup :set_mox_global

  # Both stores are read by one question now ("when did she last train?"), so every
  # test that stubs one has to answer for the other. An empty set log is the
  # do-nothing default; the tests about sets override it.
  setup do
    stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> {:ok, []} end)
    :ok
  end

  @goal_id "11111111-1111-1111-1111-111111111111"

  # Regression guard: the check function used to call
  # BotArmyFitness.FitnessStore.get_all_fitness_goals/0 and
  # .get_last_workout_date/1 — a module that does not exist — so every reminder
  # cycle raised UndefinedFunctionError, was rescued, and returned []. The
  # "workout" reminder was a permanent no-op.

  describe "check_workouts_needed/0" do
    test "reports a goal with no workouts on record at the never-worked-out tier" do
      stub_stores([goal()], [])

      assert Scheduler.check_workouts_needed() == [{@goal_id, 999}]
    end

    test "reports days since the most recent workout" do
      stub_stores([goal()], [workout(days_ago(5))])

      assert Scheduler.check_workouts_needed() == [{@goal_id, 5}]
    end

    test "uses the most recent workout when several exist" do
      stub_stores([goal()], [workout(days_ago(30)), workout(days_ago(2)), workout(days_ago(9))])

      assert Scheduler.check_workouts_needed() == [{@goal_id, 2}]
    end

    test "picks the newest date regardless of day-of-month ordering" do
      # 2026-08-31 is older than 2026-09-01 but has the larger day number, and
      # structural comparison of Date structs compares the day field before the
      # month — so the wrong workout gets picked.
      older = ~D[2026-08-31]
      newer = ~D[2026-09-01]

      assert Scheduler.latest_workout_date([workout_on(older), workout_on(newer)]) == newer
      assert Scheduler.latest_workout_date([workout_on(newer), workout_on(older)]) == newer
      assert Scheduler.latest_workout_date([]) == nil
    end

    test "stays quiet when a workout was logged today" do
      stub_stores([goal()], [workout(days_ago(0))])

      assert Scheduler.check_workouts_needed() == []
    end

    test "handles workout dates stored as ISO strings and as Date structs" do
      stub_stores([goal()], [workout_string(days_ago(4))])

      assert Scheduler.check_workouts_needed() == [{@goal_id, 4}]
    end

    test "reports every active goal" do
      other = "22222222-2222-2222-2222-222222222222"
      stub_stores([goal(), goal(other)], [workout(days_ago(3))])

      assert Enum.sort(Scheduler.check_workouts_needed()) ==
               Enum.sort([{@goal_id, 3}, {other, 3}])
    end

    test "does not nag about goals that are no longer active" do
      stub_stores(
        [
          goal(@goal_id, %{"status" => "completed"}),
          goal("33333333-3333-3333-3333-333333333333", %{"status" => "abandoned"})
        ],
        []
      )

      assert Scheduler.check_workouts_needed() == []
    end

    test "returns nothing when there are no goals" do
      stub_stores([], [workout(days_ago(10))])

      assert Scheduler.check_workouts_needed() == []
    end

    test "skips the cycle when the workout store read fails" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:error, :timeout} end)
      stub(BotArmyFitness.GoalStoreMock, :list, fn _tenant -> [goal()] end)

      # A failed read must not be reported as "no workouts" (999 -> urgent).
      assert Scheduler.check_workouts_needed() == []
    end

    test "survives an unexpected workout store reply" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, :not_a_list} end)
      stub(BotArmyFitness.GoalStoreMock, :list, fn _tenant -> [goal()] end)

      assert Scheduler.check_workouts_needed() == []
    end

    test "treats an unparseable workout date as no recorded workout" do
      stub_stores([goal()], [%{"id" => "w-1", "date" => "not-a-date"}])

      assert Scheduler.check_workouts_needed() == [{@goal_id, 999}]
    end

    test "survives a goal store failure" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
      stub(BotArmyFitness.GoalStoreMock, :list, fn _tenant -> raise "goal store down" end)

      assert Scheduler.check_workouts_needed() == []
    end
  end

  describe "days_since_last_workout/0" do
    test "reports the day count for the most recent workout" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, [workout(days_ago(4))]} end)

      assert Scheduler.days_since_last_workout() == {:ok, 4}
    end

    test "reports a workout logged today as zero days" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, [workout(days_ago(0))]} end)

      # The reminder cycle filters 0 out (there is nothing to nag about), but the
      # fact itself must still say 0: the social check-in asks a different question,
      # and "today" is exactly the answer that keeps the invitation quiet.
      assert Scheduler.days_since_last_workout() == {:ok, 0}
    end

    test "reports the never-worked-out sentinel when nothing is on record" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      assert Scheduler.days_since_last_workout() == {:ok, 999}
    end

    test "picks the newest date regardless of day-of-month ordering" do
      older = ~D[2026-08-31]
      newer = ~D[2026-09-01]

      # Pinning "today" here would make this test rot; the property that matters is
      # that the newer Gregorian day wins, whatever it is relative to now.
      expected = Date.diff(HouseholdDay.today(), newer)

      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout_on(older), workout_on(newer)]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, expected}
    end

    test "handles workout dates stored as ISO strings" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout_string(days_ago(4))]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 4}
    end

    test "a failed store read is an error, never 'no workouts'" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:error, :timeout} end)

      # The store's own reason is preserved so the caller can log what happened.
      assert Scheduler.days_since_last_workout() == {:error, :timeout}
    end

    test "a raising store read is an error, not a crash in the caller" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> raise "db down" end)

      assert {:error, %RuntimeError{}} = Scheduler.days_since_last_workout()
    end

    test "survives an unexpected store reply" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, :not_a_list} end)

      assert {:error, {:unexpected_store_reply, {:ok, :not_a_list}}} =
               Scheduler.days_since_last_workout()
    end

    test "an unreadable date is never-worked-out, never today" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [%{"id" => "w-1", "date" => "not-a-date"}]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 999}
    end

    test "a set is training, even on a day with no workout row" do
      # The home gym writes `workout_sets` and no `workouts` row at all, because a
      # movement is not a session. Reading only the workout log would tell her she
      # has not trained in a week while her set log is full.
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit ->
        {:ok, [%{"id" => "s-1", "date" => days_ago(2)}]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 2}
    end

    test "the newest of the two logs is the answer, not the newer kind of row" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout(days_ago(9))]}
      end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit ->
        {:ok, [%{"id" => "s-1", "date" => days_ago(1)}]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 1}

      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout(days_ago(1))]}
      end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit ->
        {:ok, [%{"id" => "s-1", "date" => days_ago(9)}]}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 1}
    end

    test "an unreadable set log is an error, never a shorter history" do
      # Half a history is not "when did she last train". Reporting the workout log
      # alone would nag her about a missed workout on a day she trained, which is
      # the exact noise this bot exists not to make.
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit ->
        {:error, :timeout}
      end)

      assert Scheduler.days_since_last_workout() == {:error, :timeout}
    end

    test "a raising set store is an error, not a crash in the caller" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
      stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> raise "db down" end)

      assert {:error, %RuntimeError{}} = Scheduler.days_since_last_workout()
    end

    test "a workout and a set on the same day is still that day, not double-counted" do
      stub_stores([goal()], [workout(days_ago(3))], [%{"id" => "s-1", "date" => days_ago(3)}])

      assert Scheduler.days_since_last_workout() == {:ok, 3}
      assert Scheduler.check_workouts_needed() == [{@goal_id, 3}]
    end

    test "reads the workouts of the default tenant" do
      expect(BotArmyFitness.WorkoutStoreMock, :list, fn tenant ->
        assert tenant == BotArmyLibraryCore.Tenant.default_tenant_id()
        {:ok, []}
      end)

      assert Scheduler.days_since_last_workout() == {:ok, 999}
    end
  end

  describe "training_days/0" do
    # The rotation's input, and the same rule about what a set is: a day with three sets is
    # one training day. Counted as a union and not as a sum, because a day she squatted and
    # hiked is one day off the couch.
    test "counts the days, not the rows, across both logs" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [workout(~D[2026-10-05])]}
      end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        # Two days of sets, three sets in all, one of them the day she also logged a
        # workout. Four dates, three distinct days.
        {:ok, [~D[2026-10-05], ~D[2026-10-08], ~D[2026-10-08]]}
      end)

      assert Scheduler.training_days() == {:ok, 2}
    end

    test "a day only the set log knows is a training day" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        {:ok, [~D[2026-10-01], ~D[2026-10-03]]}
      end)

      assert Scheduler.training_days() == {:ok, 2}
    end

    test "nothing logged is zero days, which is a real answer" do
      # Not a failure: a first session is the first session. The handler is what	turns
      # this into "Push A" — and it only gets to do that because the read succeeded.
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> {:ok, []} end)

      assert Scheduler.training_days() == {:ok, 0}
    end

    test "a store that cannot answer is an error, never a shorter history" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        {:error, :timeout}
      end)

      assert Scheduler.training_days() == {:error, :timeout}
    end

    test "a raising store is an error, not a crash in the caller" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        raise "db down"
      end)

      assert {:error, %RuntimeError{}} = Scheduler.training_days()
    end

    test "an unexpected store reply is an error rather than an empty log" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> :no_reply end)

      assert {:error, {:unexpected_store_reply, :no_reply}} = Scheduler.training_days()
    end

    test "a set-log day that is not a date is an error, not a day quietly dropped" do
      # The store returns `Date` structs for the days it counted. Anything else means the
      # seam changed, and a day silently dropped is a training day the rotation forgets.
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        {:ok, [~D[2026-10-01], "2026-10-03"]}
      end)

      assert Scheduler.training_days() == {:error, {:not_a_date, "2026-10-03"}}
    end

    test "reads the default tenant, the same one the reminders read" do
      expect(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn tenant ->
        assert tenant == BotArmyLibraryCore.Tenant.default_tenant_id()
        {:ok, []}
      end)

      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, []} end)

      assert Scheduler.training_days() == {:ok, 0}
    end
  end

  defp stub_stores(goals, workouts, sets \\ []) do
    stub(BotArmyFitness.GoalStoreMock, :list, fn _tenant -> goals end)
    stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, workouts} end)
    stub(BotArmyFitness.WorkoutSetStoreMock, :recent, fn _tenant, _limit -> {:ok, sets} end)
  end

  defp goal(id \\ @goal_id, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "title" => "Run 5k",
        "target_date" => Date.to_iso8601(Date.add(HouseholdDay.today(), 30)),
        "status" => "active",
        "tenant_id" => "00000000-0000-0000-0000-000000000001"
      },
      overrides
    )
  end

  defp workout(%Date{} = date), do: %{"id" => "w-#{date}", "date" => date}
  defp workout_on(%Date{} = date), do: %{"id" => "w-on-#{date}", "date" => date}
  defp workout_string(date), do: %{"id" => "w-#{date}", "date" => Date.to_iso8601(date)}
  defp days_ago(days), do: Date.add(HouseholdDay.today(), -days)
end

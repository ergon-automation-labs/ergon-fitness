defmodule BotArmyFitness.SchedulerTest do
  use ExUnit.Case

  @moduletag :core

  import Mox

  alias BotArmyFitness.Scheduler

  setup :set_mox_global

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

  defp stub_stores(goals, workouts) do
    stub(BotArmyFitness.GoalStoreMock, :list, fn _tenant -> goals end)
    stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:ok, workouts} end)
  end

  defp goal(id \\ @goal_id, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "title" => "Run 5k",
        "target_date" => Date.to_iso8601(Date.add(Date.utc_today(), 30)),
        "status" => "active",
        "tenant_id" => "00000000-0000-0000-0000-000000000001"
      },
      overrides
    )
  end

  defp workout(%Date{} = date), do: %{"id" => "w-#{date}", "date" => date}
  defp workout_on(%Date{} = date), do: %{"id" => "w-on-#{date}", "date" => date}
  defp workout_string(date), do: %{"id" => "w-#{date}", "date" => Date.to_iso8601(date)}
  defp days_ago(days), do: Date.add(Date.utc_today(), -days)
end

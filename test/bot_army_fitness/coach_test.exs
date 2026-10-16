defmodule BotArmyFitness.CoachTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.Coach
  alias BotArmyFitness.ExerciseCatalog

  # A set row in the shape the store answers with, newest first when in a list. Only the
  # fields `Progression.next_load/1` and the coach's own "which one did she do last" read
  # are here.
  defp set(exercise, date, amount, load_value) do
    %{
      "id" => "00000000-0000-0000-0000-0000000000#{String.slice(date, 8, 2)}",
      "exercise" => exercise,
      "measure" => "reps",
      "amount" => amount,
      "load_kind" => "level",
      "load_value" => load_value,
      "date" => date
    }
  end

  describe "the rotation" do
    test "holds the sessions the method names, each with a label and no duplicate value" do
      sessions = Coach.sessions()

      assert length(sessions) == 4
      assert Coach.session_count() == 4

      values = Enum.map(sessions, & &1["value"])

      assert values == Enum.uniq(values)
      assert values == ~w(push_a pull_a push_b pull_b)

      for session <- sessions do
        assert is_binary(session["label"]) and session["label"] != ""
        assert is_list(session["slots"])
      end
    end

    test "no session asks for more than six slots" do
      # The one bound left on the menu. `ExerciseCatalog` is allowed to be long — it is a
      # vocabulary, and the whole point of the extra movements is that they exist — but a
      # session is a thing a person reads on a bad morning, and six is where a card stops
      # being a list she can hold.
      for session <- Coach.sessions() do
        assert length(session["slots"]) <= 6,
               "#{session["value"]} has #{length(session["slots"])} slots"
      end
    end

    test "every slot says what it is for, how many sets, and offers movements from the gym" do
      for session <- Coach.sessions(), slot <- session["slots"] do
        assert is_binary(slot["slot"]) and slot["slot"] != ""
        assert is_integer(slot["sets"]) and slot["sets"] > 0
        assert slot["works"] != [], "#{slot["slot"]} is there to work nothing"

        for group <- slot["works"] do
          assert ExerciseCatalog.group_value?(group), "#{slot["slot"]} works #{group}"
        end

        assert slot["options"] != [], "#{slot["slot"]} offers no movement"
        assert slot["options"] == Enum.uniq(slot["options"])

        for option <- slot["options"] do
          assert ExerciseCatalog.known?(option),
                 "#{slot["slot"]} offers #{option}, which this gym does not have"
        end
      end
    end

    test "a slot's movements each work a group the slot is there for" do
      # Not "every movement hits every named group" — a slot names the shape it is after and
      # a movement that helps elsewhere still belongs (a clean & press is a press and works
      # the backside too). What must hold is that nothing in a slot is irrelevant to it,
      # which is what makes the slot's own sentence true.
      for session <- Coach.sessions(), slot <- session["slots"], option <- slot["options"] do
        assert Enum.any?(slot["works"], &ExerciseCatalog.works?(option, &1)),
               "#{option} in '#{slot["slot"]}' works none of #{inspect(slot["works"])}"
      end
    end

    test "the four sessions between them work every group the gym can reach" do
      # The receipt for the whole request: a full programme with this equipment. Every group
      # in the vocabulary is named by some slot, so a week of the rotation is a week that
      # touched everything the house can train — including the lower back, which only the
      # hinges reach and which `"legs behind"` therefore names out loud.
      assert Coach.covered_groups() == ExerciseCatalog.groups()
      assert length(Coach.covered_groups()) == 18
    end

    test "the method is narrower than the menu, and says so" do
      # The menu has to be reachable; the method has to be short. The timed dip hold is the
      # one movement no session asks for: it is a hold, and the slots that want a chest press
      # want a press. It stays in the catalog for the free picker and for a day when a hold
      # is the right answer, and this assertion is where that fact lives rather than in
      # someone's memory.
      unused = Enum.map(ExerciseCatalog.exercises(), & &1["value"]) -- Coach.movements()

      assert unused == ["dip_hold_top"]
      assert length(Coach.movements()) == 51
    end
  end

  describe "position/1 and owed_on/1" do
    # The rotation is turned by a day, so these tests read the anchor out of the module rather
    # than restating it: the anchor is allowed to move, and what must not move is that the
    # anchor's own day is the first session.
    test "the anchor's day is the first session, and the four come round with the calendar" do
      anchor = Coach.rotation_anchor()

      assert Coach.position(anchor) == 0
      assert Coach.owed_on(anchor)["value"] == "push_a"

      days = for offset <- 0..4, do: Date.add(anchor, offset)

      assert Enum.map(days, &Coach.owed_on(&1)["value"]) ==
               ~w(push_a pull_a push_b pull_b push_a)

      assert Enum.map(days, &Coach.position/1) == [0, 1, 2, 3, 0]
    end

    test "the day turns it: tomorrow is a different session with nothing trained in between" do
      # The whole point of the change. `days_trained` no longer appears in the rule at all, so
      # a rest day moves the method on — which is what a card labelled "today's session"
      # promises. The test says it in the shape the bug was reported in: same log, new day.
      day = Coach.rotation_anchor()

      assert Coach.owed_on(day) != Coach.owed_on(Date.add(day, 1))
    end

    test "a day before the anchor wraps to the end of the rotation, not behind it" do
      # `rem/2` answers -1 here, and `Enum.at/2` reads -1 as *the last* session — the right
      # answer by accident, and the wrong one the moment the rotation holds something else.
      # The day is wrapped with `Integer.mod/2`, and this is where that is pinned.
      day_before = Date.add(Coach.rotation_anchor(), -1)

      assert Coach.position(day_before) == 3
      assert Coach.owed_on(day_before)["value"] == "pull_b"
    end

    test "the answer is a function of the day alone, however far from the anchor it is" do
      anchor = Coach.rotation_anchor()

      assert Coach.owed_on(Date.add(anchor, 40)) == Coach.owed_on(anchor)
      assert Coach.owed_on(Date.add(anchor, 41)) == Coach.owed_on(Date.add(anchor, 1))
    end

    test "the anchor keeps Push A on the day the old counting rule was answering" do
      # Not a rule of the method — a rule of the migration. 2026-10-16 was the day the
      # day-count rule stood on Push A, and the anchor was chosen so the card answered the
      # same session the day it changed hands.
      assert Date.diff(~D[2026-10-16], Coach.rotation_anchor()) |> Integer.mod(4) == 0
    end

    test "refuses a day it cannot read" do
      # A failed read must not look like the anchor's day. `nil` is the answer for anything
      # that is not a `Date`, and the handler turns that into a read failure rather than into
      # "Push A".
      assert Coach.owed_on(nil) == nil
      assert Coach.owed_on("2026-01-01") == nil
      assert Coach.owed_on(~N[2026-01-01 09:00:00]) == nil
      assert Coach.owed_on(:today) == nil

      assert Coach.position(nil) == nil
      assert Coach.position(1) == nil
    end
  end

  describe "plan/2" do
    setup do
      %{session: Coach.owed_on(Coach.rotation_anchor())}
    end

    test "offers every movement of every slot, even with nothing in her log", %{session: session} do
      plan = Coach.plan(session, %{})

      assert plan["value"] == "push_a"
      assert length(plan["slots"]) == 6

      for {slot, source} <- Enum.zip(plan["slots"], session["slots"]) do
        assert slot["slot"] == source["slot"]
        assert slot["sets"] == source["sets"]
        assert Enum.map(slot["movements"], & &1["value"]) == source["options"]

        # No number and no "last time" for a movement she has never logged — and the
        # movement is still offered, because a menu that hid its unstarted items would
        # never let her start one.
        for movement <- slot["movements"] do
          assert movement["next"] == nil
          assert movement["last"] == nil
        end

        assert slot["recent"] == nil
      end
    end

    test "carries the movement's own window and its label, straight from the catalog", %{
      session: session
    } do
      slot = Coach.plan(session, %{})["slots"] |> List.first()
      press = Enum.find(slot["movements"], &(&1["value"] == "cable_chest_press"))

      assert press["label"] == "Cable chest press"
      assert press["measure"] == "reps"
      assert press["min"] == 8
      assert press["max"] == 12
    end

    test "the number beside a movement is her own next set, from Progression", %{session: session} do
      history = %{"cable_chest_press" => [set("cable_chest_press", "2026-10-13", 8, 10)]}
      slot = Coach.plan(session, history)["slots"] |> List.first()
      press = Enum.find(slot["movements"], &(&1["value"] == "cable_chest_press"))

      # Bottom of the window at level 10: the count climbs and the load does not move.
      # The coach holds no rule of its own here — this is `Progression.next_load/1`'s
      # answer travelling through untouched.
      assert press["next"] == %{
               "exercise" => "cable_chest_press",
               "measure" => "reps",
               "amount" => 10,
               "load_kind" => "level",
               "load_value" => 10
             }

      assert press["last"] == "2026-10-13"

      # Every other movement in the slot is still offered, and each one still says nothing
      # rather than borrowing the number the first movement earned.
      others = slot["movements"] |> Enum.reject(&(&1["value"] == "cable_chest_press"))

      assert others != []
      assert Enum.all?(others, &(&1["next"] == nil))
    end

    test "names the movement she did most recently, and never a movement with no history", %{
      session: session
    } do
      history = %{
        "floor_press" => [set("floor_press", "2026-10-01", 8, 10)],
        "dip" => [set("dip", "2026-10-09", 5, nil)]
      }

      slot = Coach.plan(session, history)["slots"] |> List.first()

      assert slot["recent"] == "dip"
      assert slot["movements"] |> Enum.map(& &1["value"]) |> Enum.member?("floor_press")
    end

    test "a tie keeps the slot's own order, so the same log always names the same movement", %{
      session: session
    } do
      same_day = "2026-10-09"

      history = %{
        "cable_chest_press" => [set("cable_chest_press", same_day, 8, 10)],
        "floor_press" => [set("floor_press", same_day, 8, 10)]
      }

      slot = Coach.plan(session, history)["slots"] |> List.first()

      # `cable_chest_press` is first in `"a press"`'s options, so a tie falls to it.
      assert slot["recent"] == "cable_chest_press"
    end

    test "an empty history list is the same as no history at all", %{session: session} do
      slot = Coach.plan(session, %{"dip" => []})["slots"] |> List.first()
      dip = Enum.find(slot["movements"], &(&1["value"] == "dip"))

      assert dip["next"] == nil
      assert dip["last"] == nil
      assert slot["recent"] == nil
    end

    test "a history in some other shape is read as no history rather than raising", %{
      session: session
    } do
      # The store is the caller that decides the shape; this is the boundary a bad one
      # crosses. A coach that raised here would take the consumer's other subscriptions
      # down with it.
      slot = Coach.plan(session, %{"dip" => :not_a_list})["slots"] |> List.first()
      dip = Enum.find(slot["movements"], &(&1["value"] == "dip"))

      assert dip["next"] == nil
      assert slot["recent"] == nil
    end

    test "says which groups the session's slots work, in the catalog's own order", %{
      session: session
    } do
      plan = Coach.plan(session, %{})

      assert plan["groups"] == [
               "chest",
               "front_delts",
               "side_delts",
               "traps",
               "triceps",
               "abs",
               "obliques"
             ]
    end

    test "a session it cannot read is nil, not a plan" do
      assert Coach.plan(nil, %{}) == nil
      assert Coach.plan("push_a", %{}) == nil
      assert Coach.plan(Coach.owed_on(Coach.rotation_anchor()), :not_a_history) == nil
    end
  end
end

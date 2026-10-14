defmodule BotArmyFitness.ProgressionTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.Progression

  # The rule is double progression: the count moves first through the movement's own
  # window, and the load moves one rung of the piece's own ladder only once the count has
  # topped that window out. Nothing here reads a clock or a session count — the newest set
  # is the whole input — so every case below is one set and an expected answer.

  describe "the count moves first" do
    test "mid-window, the same load with more reps" do
      assert Progression.next_load([set("goblet_squat", 8, 25.0)]) == %{
               "exercise" => "goblet_squat",
               "measure" => "reps",
               "amount" => 10,
               "load_kind" => "kg",
               "load_value" => 25.0
             }
    end

    test "a count below the whole window climbs to its bottom, not past it" do
      # A negative pull-up is 3-to-6 on the bar, and the coarsest window this gym walks is
      # 5, 8, 10, 12, 20 — so the only step inside 3..6 is 5.
      assert %{"amount" => 5, "load_value" => nil} =
               Progression.next_load([set("negative_pull_up", 3)])
    end

    test "a bodyweight movement carries no number, and only its count moves" do
      assert %{"amount" => 8, "load_value" => nil, "load_kind" => "bodyweight"} =
               Progression.next_load([set("pull_up", 5, nil, "bodyweight")])
    end

    test "the answer is the newest set's, and the history behind it changes nothing" do
      # The list is the shape the question has, not a window this rule averages over: a
      # set she did a month ago and one she did an hour ago are the same input.
      newest = set("goblet_squat", 8, 25.0)
      older = set("goblet_squat", 12, 40.0)

      assert Progression.next_load([newest]) == Progression.next_load([newest, older])
    end
  end

  describe "the load moves only when the count has topped out" do
    test "the dumbbells go up one step of their own ladder and the count resets" do
      # 10..55 by 5, and the movement's window for a goblet squat tops out at 12.
      assert Progression.next_load([set("goblet_squat", 12, 25.0)]) == %{
               "exercise" => "goblet_squat",
               "measure" => "reps",
               "amount" => 8,
               "load_kind" => "kg",
               "load_value" => 30.0
             }
    end

    test "the kettlebell walks its seven settings, which are a list and not a step" do
      assert %{"amount" => 10, "load_value" => 31.0} =
               Progression.next_load([set("kb_swing", 12, 24.5)])
    end

    test "the MaxPRO's level goes up by one, because a dial position is not a weight" do
      assert %{"amount" => 8, "load_value" => 25, "load_kind" => "level"} =
               Progression.next_load([set("cable_chest_press", 12, 24.0, "level")])
    end

    test "a count past the top of the window is at the top, not off the end of it" do
      # The bot does not enforce the rep list, so a caller may store 13 for a 10..15
      # movement. Thirteen is past the top of the walkable window, so the load moves.
      assert %{"amount" => 10, "load_value" => 31.0} =
               Progression.next_load([set("kb_swing", 13, 24.5)])
    end

    test "a stored float that is a rung to within a rounding error is that rung" do
      assert Progression.next_load([set("kb_swing", 12, 24.4999999)]) ==
               Progression.next_load([set("kb_swing", 12, 24.5)])
    end
  end

  describe "\"top\" — the count is at the top and there is no higher number" do
    test "the top of the dumbbell ladder" do
      assert Progression.next_load([set("goblet_squat", 12, 55.0)]) == "top"
    end

    test "the top of the kettlebell's settings" do
      assert Progression.next_load([set("kb_swing", 12, 44.0)]) == "top"
    end

    test "the clutch, which locks at 25 rather than continuing" do
      assert Progression.next_load([set("cable_chest_press", 12, 25.0, "level")]) == "top"
    end

    test "a bodyweight movement, which has no ladder at all to climb" do
      assert Progression.next_load([set("pull_up", 10, nil, "bodyweight")]) == "top"
    end

    test "topping out a bodyweight window at a load she added is still the top" do
      # A belt's kilos are not a ladder this catalog knows, so there is no rung to name.
      # The alternative — inventing a kilogram — is exactly what the catalog refuses.
      assert Progression.next_load([set("pull_up", 10, 10.0, "bodyweight")]) == "top"
    end
  end

  describe "silence is an answer too" do
    test "no sets at all" do
      assert Progression.next_load([]) == nil
      assert Progression.next_load(nil) == nil
      assert Progression.next_load(%{}) == nil
    end

    test "a movement this house's gym does not have" do
      assert Progression.next_load([set("cable_crossover", 12, 25.0)]) == nil
      assert Progression.next_load([%{"amount" => 12}]) == nil
    end

    test "a hold counts seconds, and adding time is not this rule" do
      assert Progression.next_load([set("dead_hang", 30, nil, "bodyweight")]) == nil
      assert Progression.next_load([set("l_sit", 20, nil, "bodyweight")]) == nil
    end

    test "a count that is not a whole number above zero" do
      assert Progression.next_load([set("kb_swing", 7.5, 24.5)]) == nil
      assert Progression.next_load([set("kb_swing", 0, 24.5)]) == nil
      assert Progression.next_load([set("kb_swing", "twelve", 24.5)]) == nil
      assert Progression.next_load([set("kb_swing", nil, 24.5)]) == nil
    end

    test "a laddered piece whose set says nothing about where on the ladder she is" do
      # There *is* a rung above 25 on the dumbbells. What is missing is where she is, and
      # guessing the bottom of the ladder is a training decision this bot does not make.
      assert Progression.next_load([set("goblet_squat", 12, nil)]) == nil
      assert Progression.next_load([set("goblet_squat", 12, "heavy")]) == nil
    end
  end

  describe "a suggestion is not a row that happened" do
    test "the answer carries the row's own words and nothing that belongs to a day" do
      answer = Progression.next_load([set("goblet_squat", 12, 25.0)])

      assert Map.keys(answer) |> Enum.sort() ==
               ~w(amount exercise load_kind load_value measure)

      refute Map.has_key?(answer, "date")
      refute Map.has_key?(answer, "id")
      refute Map.has_key?(answer, "tenant_id")
    end
  end

  defp set(exercise, amount, load_value \\ nil, load_kind \\ "kg") do
    %{
      "id" => UUID.uuid4(),
      "exercise" => exercise,
      "measure" => "reps",
      "amount" => amount,
      "load_kind" => load_kind,
      "load_value" => load_value,
      "date" => "2026-10-10"
    }
  end
end

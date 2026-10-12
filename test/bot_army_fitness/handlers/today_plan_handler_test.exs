defmodule BotArmyFitness.Handlers.TodayPlanHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyFitness.Handlers.TodayPlanHandler
  alias BotArmyFitness.Schemas.DailyPlan
  alias BotArmyFitness.WorkoutTypes

  @tenant_id "00000000-0000-0000-0000-000000000001"
  @user_id "00000000-0000-0000-0000-000000000002"
  @jan_first ~D[2026-01-01]

  describe "build_plan/3 — the crash that killed the consumer" do
    test "never raises, for any day of the year" do
      # The old code called `workout_type.downcase()` in the description, i.e.
      # `:erlang.apply("Yoga", :downcase, [])`. Every value of @workout_types
      # raised, terminating BotArmyFitness.NATS.Consumer and dropping every
      # fitness subscription with it.
      for day <- 0..366 do
        plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, Date.add(@jan_first, day))

        assert is_binary(plan["workout_type"])
        assert is_binary(plan["description"])
      end
    end

    test "the description carries the label, and workout_type is canonical" do
      plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, @jan_first)

      assert String.starts_with?(
               plan["description"],
               WorkoutTypes.label(plan["workout_type"]) <> " for "
             )

      assert WorkoutTypes.known?(plan["workout_type"])
    end

    test "every rotation slot is a canonical type" do
      for day <- 0..40 do
        plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, Date.add(@jan_first, day))

        assert plan["workout_type"] in WorkoutTypes.types()
      end
    end

    test "is a pure function of (tenant, user, date)" do
      assert Map.drop(TodayPlanHandler.build_plan(@tenant_id, @user_id, @jan_first), [
               "generated_at"
             ]) ==
               Map.drop(TodayPlanHandler.build_plan(@tenant_id, @user_id, @jan_first), [
                 "generated_at"
               ])
    end

    test "different users on the same day get a different rotation seed" do
      types =
        for user <- ~w(a b c d e f g h),
            do: TodayPlanHandler.build_plan(@tenant_id, user, @jan_first)

      assert types |> Enum.map(& &1["workout_type"]) |> Enum.uniq() |> length() > 1
    end

    test "duration stays inside 30..60 minutes" do
      for day <- 0..366 do
        plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, Date.add(@jan_first, day))

        assert plan["duration_minutes"] in 30..60
      end
    end

    test "intensity is one of the three the surfaces offer" do
      for day <- 0..366 do
        plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, Date.add(@jan_first, day))

        assert plan["intensity"] in WorkoutTypes.intensities()
      end
    end

    test "estimated calories follow the intensity multiplier" do
      for day <- 0..32 do
        plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, Date.add(@jan_first, day))

        assert plan["estimated_calories"] ==
                 plan["duration_minutes"] * multiplier(plan["intensity"])
      end
    end
  end

  describe "format_response/1" do
    test "returns ok with exactly the six fields the card reads" do
      plan = TodayPlanHandler.build_plan(@tenant_id, @user_id, @jan_first)
      response = TodayPlanHandler.format_response(plan)

      assert response["ok"] == true

      assert response["data"] |> Map.keys() |> Enum.sort() ==
               ~w(duration_minutes estimated_calories intensity plan title workout_type)
    end

    test "does not invent a field the plan does not carry" do
      response = TodayPlanHandler.format_response(%{"description" => "a walk"})

      assert response["data"]["plan"] == "a walk"
      assert response["data"]["intensity"] == nil
      assert response["data"]["estimated_calories"] == nil
    end
  end

  describe "format_stored_plan/1 — the second crash (a struct read with Access)" do
    test "uses the stored plan_json map when it carries a description" do
      plan = %DailyPlan{
        id: Ecto.UUID.generate(),
        tenant_id: @tenant_id,
        date: @jan_first,
        type: "strength",
        estimated_minutes: 45,
        plan_json: %{
          "title" => "Strength Day",
          "workout_type" => "strength",
          "duration_minutes" => 45,
          "intensity" => "moderate",
          "estimated_calories" => 450,
          "description" => "strength for 45 minutes at moderate intensity."
        }
      }

      response = TodayPlanHandler.format_stored_plan(plan)

      assert response["ok"] == true
      assert response["data"]["title"] == "Strength Day"
      assert response["data"]["plan"] == "strength for 45 minutes at moderate intensity."
    end

    test "falls back to the struct's columns instead of raising" do
      # The old code did `plan["description"]` on this struct, which raised
      # UndefinedFunctionError (`DailyPlan.fetch/2` is not defined).
      plan = %DailyPlan{
        tenant_id: @tenant_id,
        date: @jan_first,
        type: "cycling",
        estimated_minutes: 40,
        motivational_quote: "The forge is warm.",
        plan_json: %{"generated" => true}
      }

      response = TodayPlanHandler.format_stored_plan(plan)

      assert response["ok"] == true
      assert response["data"]["title"] == "cycling"
      assert response["data"]["workout_type"] == "cycling"
      assert response["data"]["duration_minutes"] == 40
      assert response["data"]["plan"] == "The forge is warm."
    end

    test "prefers notes when there is no motivational quote" do
      plan = %DailyPlan{
        tenant_id: @tenant_id,
        date: @jan_first,
        type: "yoga",
        estimated_minutes: 30,
        notes: "Take it slow.",
        plan_json: %{}
      }

      assert TodayPlanHandler.format_stored_plan(plan)["data"]["plan"] == "Take it slow."
    end
  end

  defp multiplier("intense"), do: 12
  defp multiplier("moderate"), do: 10
  defp multiplier(_), do: 7
end

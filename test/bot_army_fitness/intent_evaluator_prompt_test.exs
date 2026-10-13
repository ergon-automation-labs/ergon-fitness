defmodule BotArmyFitness.IntentEvaluatorPromptTest do
  use ExUnit.Case
  @moduletag :core

  import Mox

  alias BotArmyFitness.IntentEvaluator

  setup :set_mox_global

  # The live crash payload (air, 2026-10-13): `context.summary.idle_minutes` is the
  # aggregate that `AccumulatedContext.compute_summary/1` produces, not a scalar.
  defp series_context(idle_minutes) do
    %{
      bot_name: "fitness",
      entries: [],
      entry_count: 1,
      summary: %{
        idle_minutes: %{
          count: 1,
          values: [idle_minutes],
          latest: %{
            type: :idle_minutes,
            value: idle_minutes,
            metadata: %{source: "pulse"},
            observed_at: ~U[2026-10-13 12:35:32.992898Z]
          }
        }
      }
    }
  end

  describe "build_suggest_workout_defer_prompt/3" do
    test "renders the hours from a summary aggregate instead of raising" do
      details = %{score: 0.7, reason: :low_roll}

      assert %{"text" => text} =
               IntentEvaluator.build_suggest_workout_defer_prompt(
                 "suggest_workout",
                 details,
                 series_context(60)
               )

      assert text =~ "idle for 1 hours"
      assert text =~ "0.7"
      assert text =~ "low_roll"
    end

    test "still accepts a scalar summary" do
      context = %{summary: %{idle_minutes: 120}}

      assert %{"text" => text} =
               IntentEvaluator.build_suggest_workout_defer_prompt(
                 "suggest_workout",
                 %{score: 0.5, reason: :low_roll},
                 context
               )

      assert text =~ "idle for 2 hours"
    end

    test "defaults to zero hours when the type is absent" do
      assert %{"text" => text} =
               IntentEvaluator.build_suggest_workout_defer_prompt(
                 "suggest_workout",
                 %{score: 0.5, reason: :low_roll},
                 %{summary: %{}}
               )

      assert text =~ "idle for 0 hours"
    end
  end

  describe "workout_body/1" do
    test "reads the criteria out of :threshold_breakdown" do
      details = %{
        score: 0.6,
        reason: :random_boost,
        threshold_breakdown: %{
          idle_minutes: %{value: 180, threshold_min: 60},
          streak_at_risk: %{value: 0, threshold_min: 1}
        }
      }

      assert IntentEvaluator.workout_body(details) =~ "idle for 3 hours"
    end

    test "reports a streak at risk ahead of idleness" do
      details = %{
        score: 0.9,
        reason: :clear_threshold,
        threshold_breakdown: %{
          idle_minutes: %{value: 60},
          streak_at_risk: %{value: 1}
        }
      }

      assert IntentEvaluator.workout_body(details) =~ "streak is at risk"
    end

    test "falls back to the generic invitation when nothing is known" do
      details = %{score: 0.5, reason: :random_boost, threshold_breakdown: %{}}

      assert IntentEvaluator.workout_body(details) =~ "Time for a workout?"
    end
  end

  describe "the social check-in's days_since_workout" do
    test "the invite carries the real count, not the dead branch's zero" do
      message = IntentEvaluator.social_check_in_message("fitness", 5, 0.66)

      assert message["event"] == "gossip.social.invite"
      assert message["payload"]["to_bot"] == "gtd_bot"
      assert message["payload"]["from_bot"] == "fitness"
      assert message["payload"]["days_since_workout"] == 5
      assert message["payload"]["adaptive_score"] == 0.66
      assert message["payload"]["cooldown_seconds"] == 86_400
    end

    test "an unreadable store skips the invite instead of guessing" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant -> {:error, :timeout} end)

      assert IntentEvaluator.handle_propose_social_check_in_action(
               "fitness",
               "propose_social_check_in",
               "intent-error",
               %{score: 0.9},
               []
             ) == {:error, :timeout}
    end

    test "a workout logged today is not an invitation" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [%{"id" => "w-1", "date" => Date.utc_today()}]}
      end)

      assert IntentEvaluator.handle_propose_social_check_in_action(
               "fitness",
               "propose_social_check_in",
               "intent-today",
               %{score: 0.9},
               []
             ) == :ok
    end

    test "an unreadable date counts as never-worked-out, so the invite is due" do
      stub(BotArmyFitness.WorkoutStoreMock, :list, fn _tenant ->
        {:ok, [%{"id" => "w-1", "date" => "not-a-date"}]}
      end)

      # This reaches the publish; with no broker in the hermetic suite the runtime
      # publisher reports :not_connected and the handler still answers :ok.
      assert IntentEvaluator.handle_propose_social_check_in_action(
               "fitness",
               "propose_social_check_in",
               "intent-sentinel",
               %{score: 0.9},
               []
             ) == :ok
    end
  end

  describe "extract_observations/1 records the new metric" do
    test "records days_since_workout from a pulse" do
      observations =
        IntentEvaluator.extract_observations(%{
          "observations" => %{"days_since_workout" => 4}
        })

      assert %{type: :days_since_workout, value: 4} =
               Enum.find(observations, &(&1.type == :days_since_workout))
    end

    test "ignores a zero, which is what an absent key also means" do
      observations =
        IntentEvaluator.extract_observations(%{
          "observations" => %{"days_since_workout" => 0}
        })

      refute Enum.any?(observations, &(&1.type == :days_since_workout))
    end
  end
end

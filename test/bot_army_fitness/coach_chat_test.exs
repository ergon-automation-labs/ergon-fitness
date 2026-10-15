defmodule BotArmyFitness.CoachChatTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.{Coach, CoachChat, ExerciseCatalog}

  describe "system_prompt/0" do
    test "refuses an invented movement, a chosen plan, and a number set for her" do
      prompt = CoachChat.system_prompt()

      assert prompt =~ "Never invent one"
      assert prompt =~ "Do not choose a session or a movement for her"
      assert prompt =~ "Do not set a number for her"
      assert prompt =~ "No streaks, no scores"
    end

    test "the facts it may use are named as the only facts there are" do
      assert CoachChat.system_prompt() =~ "THE GYM, TODAY'S SESSION and HER LOG"
    end
  end

  describe "gym/0" do
    test "names every piece, every area, and every movement in the catalog" do
      gym = CoachChat.gym()

      for equipment <- ExerciseCatalog.equipment(), do: assert(gym =~ equipment["label"])
      for area <- ExerciseCatalog.area_options(), do: assert(gym =~ area["label"])

      for exercise <- ExerciseCatalog.exercises(), do: assert(gym =~ exercise["label"])
    end

    test "carries the MaxPRO's real set-up, so the answer does not seat her on a bench" do
      gym = CoachChat.gym()

      assert gym =~ "MaxPRO"
      assert gym =~ "floor"
      assert gym =~ "without the bench attachment"
    end

    test "a number on a piece is described the way the piece shows it" do
      gym = CoachChat.gym()

      # The MaxPRO is a level, not a weight — the mistake the load kind exists to prevent.
      assert gym =~ "resistance level 1–25"
      assert gym =~ "kg, at 5, 11.5, 18, 24.5, 31, 37.5, 44"
      assert gym =~ "bodyweight"
    end
  end

  describe "facts/1" do
    test "spells out today's session and the number the bot says to reach for" do
      session = Coach.owed(0) |> Coach.plan(%{})
      facts = CoachChat.facts(%{today: session, days_trained: 0, last: nil})

      assert facts =~ session["label"]
      assert facts =~ "she has trained 0 days"
      assert facts =~ "a press"
      assert facts =~ "works chest, front shoulders, triceps"
      # She has no history, so no movement has a number yet — and the silence is said aloud.
      assert facts =~ "no number to reach for yet — hers to set"
    end

    test "a number from her log is read back, and a bodyweight movement is not given a weight" do
      history = %{
        "cable_row" => [
          %{
            "exercise" => "cable_row",
            "measure" => "reps",
            "amount" => 12,
            "load_kind" => "level",
            "load_value" => 8
          }
        ]
      }

      session = Coach.owed(1) |> Coach.plan(history)
      facts = CoachChat.facts(%{today: session, days_trained: 1, last: nil})

      assert facts =~ "Seated cable row (level"
    end

    test "her last day is read back with its numbers" do
      facts =
        CoachChat.facts(%{
          today: nil,
          days_trained: nil,
          last: %{
            "day" => "2026-10-14",
            "movements" => [
              %{
                "value" => "kb_swing",
                "measure" => "reps",
                "amount" => 12,
                "load_kind" => "kg",
                "load_value" => 24.5
              },
              %{
                "value" => "pull_up",
                "measure" => "reps",
                "amount" => 8,
                "load_kind" => "bodyweight",
                "load_value" => nil
              }
            ]
          }
        })

      assert facts =~ "the last day she trained was 2026-10-14"
      assert facts =~ "Two-hand swing — 24.5 kg × 12 reps"
      assert facts =~ "Pull-up — 8 reps"
    end

    test "a log that could not be read is not the same fact as a log with nothing in it" do
      unreadable = CoachChat.facts(%{today: nil, days_trained: nil, last: :unreadable})
      empty = CoachChat.facts(%{today: nil, days_trained: nil, last: nil})

      assert unreadable =~ "could not be read just now"
      assert unreadable =~ "Do not say what she has or has not done"
      refute unreadable =~ "has not kept a set"

      assert empty =~ "has not kept a set yet"
    end

    test "a rotation that could not be read is said, not filled in with a session" do
      facts = CoachChat.facts(%{today: nil, days_trained: nil, last: nil})

      assert facts =~ "TODAY'S SESSION — could not be read just now"
      assert facts =~ "Do not say what today's session is"
      refute facts =~ "Push A"
    end

    test "an unreadable part does not take the room down with it" do
      facts = CoachChat.facts(%{today: nil, days_trained: nil, last: :unreadable})

      assert facts =~ "THE GYM"
      assert facts =~ "MaxPRO"
      assert facts =~ "THE MENU"
    end
  end

  describe "prompt/2" do
    test "carries her question as she asked it, under the rules and the facts" do
      prompt = CoachChat.prompt(question(), %{today: nil, days_trained: nil, last: nil})

      assert prompt =~ "You are the coach for one person's home gym"
      assert prompt =~ "THE GYM"
      assert prompt =~ "Her question: #{question()}"
      assert prompt =~ "▲"
    end
  end

  defp question, do: "is the MaxPRO on the wall, and what should I lift on it?"
end

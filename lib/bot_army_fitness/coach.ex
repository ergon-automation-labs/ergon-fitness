defmodule BotArmyFitness.Coach do
  @moduledoc """
  The method: four sessions in rotation, and what today's is.

  `ExerciseCatalog` is the menu — every movement the four pieces make possible, tagged
  with the muscle groups it works. A menu is not a method: a person standing in front of
  fifty-two movements with a foggy morning in front of her has a harder problem than
  before anyone wrote anything down. This module is the method, and it is deliberately
  small: **four sessions, six slots each, and the numbers are hers.**

  ## The rotation turns with the day

  `owed_on/1` takes the day being asked about — the house's own day,
  `BotArmyFitness.HouseholdDay.today/0` — and answers the session that day stands at. The
  four come round with the calendar from a fixed anchor, so "today's session" is a
  different session tomorrow whatever she did today: a card that says *today* answers the
  day it is opened on.

  This was a count of training days once, and the reversal was deliberate. A day-count
  rotation answered the same session every morning until she trained, which is a true
  reading of "the next session she owes herself" — but it is not what *today's session*
  means to the person reading the card. She asked for the session to turn when the day
  turns, and that is a requirement about the card, not a claim about the method: the
  method is four sessions and this is which one today stands at.

  The count of days she has trained still travels beside the session, because it is a
  true fact about her and the card says it. It no longer decides anything.

  ## A slot is what a session is for; the movements fill it

  A session is a list of *slots*: "a press", "rear shoulders", "the middle" — each with
  the groups it is there to work, how many sets the method asks for, and the movements
  that can fill it. Every slot offers more than one movement wherever the gym allows it,
  because the method should not be the reason a movement is impossible today: the cable
  is busy, the shoulder is stiff, the dip bars are folded away.

  `plan/2` fills every slot with each of its movements, each carrying **her** next number
  from `BotArmyFitness.Progression` — and names `"recent"`, the movement she did most
  recently among the ones the slot offers, or `nil` when the slot is new to her. Naming
  the recent one is a fact about her log read back to her, not a choice made for her:
  every other movement stays on the wire with its own number beside it.

  ## Nothing here is a score, and nothing here is owed

  No streak, no count, no percentage, no "you missed". A session is a proposal with the
  movements already hers. She may do the whole thing, one slot of it, or something else
  entirely, and the day turns the rotation either way — because a method that punished a
  partial day would be a boss, and this is a house.
  """

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.Progression

  # The method's own number of sets per slot. It sits on every slot rather than in a
  # constant so a session can ask for more or fewer without touching this module, and it
  # is the method's number and not hers — the count she presses and the load she loads
  # are the only numbers that come from her.
  @sets 3

  # Which day the first session is for. Any fixed date would do — the rotation only needs
  # an origin to count days from — and a fixed one is the point: an anchor that moved (to
  # the day the log was first read, say) would make "today's session" a function of when
  # the bot last started. 2026-01-01 is the day this method was written down, and with it
  # Push A falls on 2026-10-16 — the session the day-count rule was answering the day the
  # rule changed, so nothing about the card jumped when it did.
  @rotation_anchor ~D[2026-01-01]

  # Six slots is the ceiling a card can hold and a person can read on a bad morning. The
  # menu is long on purpose (it is a vocabulary, and it is `ExerciseCatalog`'s job to be
  # reachable rather than short); what a surface shows *at once* is this list, and it is
  # bounded here so a surface does not have to bound it.
  @sessions [
    %{
      "value" => "push_a",
      "label" => "Push A — press-led",
      "slots" => [
        %{
          "slot" => "a press",
          "works" => ["chest", "front_delts", "triceps"],
          "sets" => @sets,
          "options" => ["cable_chest_press", "floor_press", "dip", "dip_bar_push_up"]
        },
        %{
          "slot" => "chest on its own",
          "works" => ["chest"],
          "sets" => @sets,
          "options" => ["cable_fly"]
        },
        %{
          "slot" => "shoulders overhead",
          "works" => ["front_delts", "triceps"],
          "sets" => @sets,
          "options" => ["cable_shoulder_press", "overhead_press", "kb_clean_press"]
        },
        %{
          "slot" => "side shoulders",
          "works" => ["side_delts", "traps"],
          "sets" => @sets,
          "options" => ["cable_lateral_raise", "lateral_raise", "cable_upright_row", "kb_halo"]
        },
        %{
          "slot" => "triceps",
          "works" => ["triceps"],
          "sets" => @sets,
          "options" => ["triceps_pushdown", "cable_overhead_triceps", "dumbbell_overhead_triceps"]
        },
        %{
          "slot" => "the middle",
          "works" => ["abs", "obliques"],
          "sets" => @sets,
          "options" => ["cable_crunch", "cable_woodchop", "supported_knee_raise"]
        }
      ]
    },
    %{
      "value" => "pull_a",
      "label" => "Pull A — width first",
      "slots" => [
        %{
          "slot" => "a vertical pull",
          "works" => ["lats", "upper_back", "biceps"],
          "sets" => @sets,
          "options" => [
            "lat_pulldown",
            "pull_up",
            "chin_up",
            "negative_pull_up",
            "scapular_pull_up"
          ]
        },
        %{
          "slot" => "a row",
          "works" => ["upper_back", "lats"],
          "sets" => @sets,
          "options" => ["cable_row", "one_arm_row", "kb_row", "inverted_row"]
        },
        %{
          "slot" => "rear shoulders",
          "works" => ["rear_delts", "upper_back"],
          "sets" => @sets,
          "options" => ["cable_face_pull", "cable_reverse_fly", "rear_delt_fly"]
        },
        %{
          "slot" => "biceps",
          "works" => ["biceps", "forearms"],
          "sets" => @sets,
          "options" => ["cable_curl", "dumbbell_curl", "hammer_curl"]
        },
        %{
          "slot" => "traps and grip",
          "works" => ["traps", "forearms"],
          "sets" => @sets,
          "options" => ["cable_shrug", "dumbbell_shrug", "dead_hang", "kb_suitcase_carry"]
        },
        %{
          "slot" => "the middle",
          "works" => ["abs", "hip_flexors"],
          "sets" => @sets,
          "options" => ["hanging_knee_raise", "hanging_leg_raise", "l_sit", "kb_turkish_get_up"]
        }
      ]
    },
    %{
      "value" => "push_b",
      "label" => "Push B — overhead first",
      "slots" => [
        %{
          "slot" => "shoulders overhead",
          "works" => ["front_delts", "side_delts", "triceps"],
          "sets" => @sets,
          "options" => ["overhead_press", "cable_shoulder_press", "kb_clean_press"]
        },
        %{
          "slot" => "a press",
          "works" => ["chest", "triceps"],
          "sets" => @sets,
          "options" => ["floor_press", "dip", "dip_bar_push_up", "cable_chest_press"]
        },
        %{
          "slot" => "chest on its own",
          "works" => ["chest"],
          "sets" => @sets,
          "options" => ["cable_fly"]
        },
        %{
          "slot" => "side shoulders",
          "works" => ["side_delts", "traps"],
          "sets" => @sets,
          "options" => ["lateral_raise", "cable_lateral_raise", "cable_upright_row"]
        },
        %{
          "slot" => "triceps",
          "works" => ["triceps"],
          "sets" => @sets,
          "options" => ["cable_overhead_triceps", "triceps_pushdown", "dumbbell_overhead_triceps"]
        },
        %{
          "slot" => "legs",
          "works" => ["quads", "glutes"],
          "sets" => @sets,
          "options" => ["goblet_squat", "split_squat", "bulgarian_split_squat", "reverse_lunge"]
        }
      ]
    },
    %{
      "value" => "pull_b",
      "label" => "Pull B — thickness first",
      "slots" => [
        %{
          "slot" => "a row",
          "works" => ["upper_back", "lats"],
          "sets" => @sets,
          "options" => ["cable_row", "one_arm_row", "kb_row", "inverted_row"]
        },
        %{
          "slot" => "a vertical pull",
          "works" => ["lats", "biceps"],
          "sets" => @sets,
          "options" => ["pull_up", "chin_up", "lat_pulldown", "negative_pull_up"]
        },
        %{
          "slot" => "rear shoulders",
          "works" => ["rear_delts", "upper_back"],
          "sets" => @sets,
          "options" => ["cable_reverse_fly", "cable_face_pull", "rear_delt_fly"]
        },
        %{
          "slot" => "biceps",
          "works" => ["biceps", "forearms"],
          "sets" => @sets,
          "options" => ["hammer_curl", "dumbbell_curl", "reverse_curl", "cable_curl"]
        },
        %{
          "slot" => "traps and grip",
          "works" => ["traps", "forearms"],
          "sets" => @sets,
          "options" => ["dumbbell_shrug", "cable_shrug", "kb_suitcase_carry", "dead_hang"]
        },
        %{
          "slot" => "legs behind",
          "works" => ["glutes", "hamstrings", "lower_back", "calves"],
          "sets" => @sets,
          "options" => [
            "kb_romanian_deadlift",
            "cable_pull_through",
            "kb_swing",
            "cable_glute_kickback",
            "calf_raise"
          ]
        }
      ]
    }
  ]

  @doc "The rotation, in the order the sessions come, exactly as the method holds it."
  @spec sessions() :: [map()]
  def sessions, do: @sessions

  @doc "How many sessions the rotation holds before it comes back round."
  @spec session_count() :: non_neg_integer()
  def session_count, do: length(@sessions)

  @doc """
  Where the rotation stands on `date`: an index into `sessions/0`.

  `Integer.mod/2` rather than `rem/2` on purpose: a day before the anchor wraps to the
  end of the rotation, while `rem/2` would answer `-1`, which `Enum.at/2` reads as *the
  last session* — the right answer by accident, and the wrong answer the moment the
  rotation holds a session it does not hold now.

  Answers `nil` for anything that is not a `Date`: a caller that cannot say which day it
  is asking about has a failed read, and a failed read must not be read as "session
  one".
  """
  @spec position(term()) :: non_neg_integer() | nil
  def position(%Date{} = date),
    do: Integer.mod(Date.diff(date, @rotation_anchor), length(@sessions))

  def position(_date), do: nil

  @doc """
  The session the day `date` stands at.

  The day is `BotArmyFitness.HouseholdDay`'s, not this module's: this module only turns a
  day into a session. Answers `nil` for anything that is not a `Date`, for the same
  reason `position/1` does.
  """
  @spec owed_on(term()) :: map() | nil
  def owed_on(%Date{} = date), do: Enum.at(@sessions, position(date))

  def owed_on(_date), do: nil

  @doc """
  The day the rotation counts from.

  With `position/1`, a caller can say what an index means without restating the anchor: the
  session is `Enum.at(sessions(), position(date))`, and the day it is for is the day.
  """
  @spec rotation_anchor() :: Date.t()
  def rotation_anchor, do: @rotation_anchor

  @doc """
  One session with every slot filled: the movements each slot offers, and the set to
  reach for next on each, read from `history`.

  `history` maps a movement's value to its sets, newest first — the shape
  `BotArmyFitness.WorkoutSetStore` answers with. A movement with no key, or with an
  empty list, has no number yet: the movement is still offered, and the number beside it
  is `nil`, which is the honest answer for a movement she has never logged. Nothing here
  invents a starting weight; the first set of a new movement is a number the device shows
  her, and the rule picks up from there.

  Also names `"recent"`: among the movements this slot offers, the one whose newest set
  is the newest. Ties keep the menu's order, so the same history always answers the same
  session.
  """
  @spec plan(term(), term()) :: map() | nil
  def plan(session, history) when is_map(session) and is_map(history) do
    slots = Enum.map(session["slots"], &plan_slot(&1, history))

    session
    |> Map.put("slots", slots)
    |> Map.put("groups", groups_in(slots))
  end

  def plan(_session, _history), do: nil

  @doc """
  Every muscle group the rotation works, in the catalog's reading order.

  The receipt for "a full push/pull programme with this equipment": the four sessions
  between them name every group the gym can reach, and the test suite is what says so.
  `"legs behind"` names the lower back even though the slot is not *for* it, because the
  hinges in that slot are the only thing in the method that loads it — a group that is
  absent from every slot is one the method never asks for, and the honest fix is to say
  what the session actually works rather than to leave it unsaid.
  """
  @spec covered_groups() :: [String.t()]
  def covered_groups do
    worked =
      @sessions
      |> Enum.flat_map(& &1["slots"])
      |> Enum.flat_map(& &1["works"])
      |> MapSet.new()

    Enum.filter(ExerciseCatalog.groups(), &MapSet.member?(worked, &1))
  end

  @doc "Every movement value the rotation can ask for, in menu order, each only once."
  @spec movements() :: [String.t()]
  def movements do
    @sessions
    |> Enum.flat_map(& &1["slots"])
    |> Enum.flat_map(& &1["options"])
    |> Enum.uniq()
  end

  # The movements of one slot, each with her own next number beside it. The slot's own
  # words stay exactly as the method holds them — `"slot"` is what the slot is for and a
  # card draws it verbatim.
  defp plan_slot(slot, history) do
    movements = Enum.map(slot["options"], &movement_line(&1, history))

    slot
    |> Map.put("movements", movements)
    |> Map.put("recent", recent_movement(movements))
  end

  defp movement_line(value, history) do
    exercise = ExerciseCatalog.exercise(value) || %{}
    target = ExerciseCatalog.target(value) || %{}
    sets = Map.get(history, value)
    sets = if is_list(sets), do: sets, else: []

    %{
      "value" => value,
      "label" => exercise["label"],
      "measure" => target["measure"],
      "min" => target["min"],
      "max" => target["max"],
      "counts" => ExerciseCatalog.counts_for(value),
      "tip" => exercise["tip"],
      "last" => last_date(sets),
      "next" => Progression.next_load(sets)
    }
  end

  defp last_date([set | _rest]) when is_map(set) do
    date = set["date"]
    if is_binary(date), do: date, else: nil
  end

  defp last_date(_sets), do: nil

  # The newest `last` among the movements a slot offers, or `nil` when she has done none
  # of them. `Enum.sort_by/2` is stable, so a tie falls back to the slot's own order — the
  # same history always names the same movement.
  defp recent_movement(movements) do
    movements
    |> Enum.reject(&is_nil(&1["last"]))
    |> Enum.sort_by(& &1["last"], :desc)
    |> case do
      [%{"value" => value} | _rest] -> value
      [] -> nil
    end
  end

  defp groups_in(slots) do
    slots
    |> Enum.flat_map(& &1["works"])
    |> Enum.uniq()
    |> then(&Enum.filter(ExerciseCatalog.groups(), fn group -> group in &1 end))
  end
end

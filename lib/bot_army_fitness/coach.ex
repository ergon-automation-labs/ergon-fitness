defmodule BotArmyFitness.Coach do
  @moduledoc """
  The method: four sessions in rotation, and what today's is.

  `ExerciseCatalog` is the menu — every movement the four pieces make possible, tagged
  with the muscle groups it works. A menu is not a method: a person standing in front of
  fifty-two movements with a foggy morning in front of her has a harder problem than
  before anyone wrote anything down. This module is the method, and it is deliberately
  small: **four sessions, six slots each, and the numbers are hers.**

  ## The rotation turns on training days, not on the calendar

  `owed/1` takes the number of days she has trained — `BotArmyFitness.Scheduler`'s count
  of distinct days across the workout log and the set log — and answers the session at
  that position in the rotation. Nothing here reads a clock or a week boundary, and that
  is the whole point: a rotation that turned on the calendar would skip a session every
  time a week went sideways, and the session a person owes herself is the next one, not
  the one a Tuesday happened to want. Train four times and you have been through the
  rotation once, whether that took four days or four weeks.

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
  entirely, and the next training day the rotation turns by exactly one either way —
  because a method that punished a partial day would be a boss, and this is a house.
  """

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.Progression

  # The method's own number of sets per slot. It sits on every slot rather than in a
  # constant so a session can ask for more or fewer without touching this module, and it
  # is the method's number and not hers — the count she presses and the load she loads
  # are the only numbers that come from her.
  @sets 3

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
  The session she is owed, from the number of days she has trained.

  The count is `BotArmyFitness.Scheduler`'s, not this module's: it is a fact about the
  log, and this module only turns it into a session. Answers `nil` for a count that is
  not a whole number of days — a caller that cannot say how many days she has trained
  has a failed read, and a failed read must not be read as "session one".
  """
  @spec owed(term()) :: map() | nil
  def owed(days_trained) when is_integer(days_trained) and days_trained >= 0,
    do: Enum.at(@sessions, rem(days_trained, length(@sessions)))

  def owed(_days_trained), do: nil

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

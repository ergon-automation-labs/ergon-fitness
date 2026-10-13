defmodule BotArmyFitness.ExerciseCatalog do
  @moduledoc """
  The one vocabulary for this house's gym: the equipment that is here, the movements
  each piece makes possible, and what a load means on each.

  `WorkoutTypes` answers "what kind of activity was it" — running, strength, yoga —
  and that is the vocabulary a *stored row* folds onto. It is deliberately coarse: it
  can say `strength` and cannot say "goblet squat at 15 kg". A menu for a home gym
  needs the second sentence, so this module holds the equipment and the movements,
  and it holds them in one place for the same reason `WorkoutTypes` exists: four
  vocabularies disagreed before that module did, and a picker with its own copy would
  be the fifth.

  ## Three load kinds, because a weight is not one thing

  Each piece of equipment declares what a number *means* on it:

    * `"kg"`         — kilograms, and the equipment carries the settings it actually
                       offers (dumbbells step from 10 by 5; the kettlebell has seven
                       discrete settings, so its ladder is a list and not a step).
    * `"level"`      — the device's own resistance level. The MaxPRO dials a
                       PowerClutch, not a weight stack: 25 levels, and the clutch
                       stops there — it locks rather than continuing past 25. No
                       continuous kilogram scale. Recording a "kg" for it would
                       invent a number the device never showed.
    * `"bodyweight"` — the body is the load. A number, when one is recorded, is load
                       *added* (a belt) or *taken away* (an assist), so it is optional
                       and absent means the body alone.

  A surface therefore never has to know which unit to ask for: it reads the kind off
  the wire with the equipment, and a suggestion (later) walks the equipment's own
  ladder instead of adding a "reasonable" kilogram.

  ## Nothing here is a score

  The catalog is a menu of what the gym makes possible, with a rep range per movement
  and nothing else. It has no order of merit, no programme, no progression rule and no
  streak — those are the bot's decisions to make from what she actually did, and a
  menu that ranked its own items would be a curriculum, which this is not.

  ## The equipment is the house's, not the surface's

  Seeding a new piece of kit is an edit to `@equipment` — a fact about the home, not
  user data, and so not a migration. The pairs travel on `fitness.workout.options`
  beside the activities and intensities, and a surface draws them whole or not at all,
  the same contract `WorkoutTypes.type_options/0` has.
  """

  @kg "kg"
  @level "level"
  @bodyweight "bodyweight"

  # The gym, in the order a picker should offer it. `load` is what a number means;
  # `min`/`step` and `settings` are the ladder the device actually has, and are absent
  # when the load is the body (there is no ladder for a pull-up).
  #
  # The MaxPRO's ladder tops out at 25: the PowerClutch locks at its last level rather
  # than turning further, so 25 is the top of the range and not a round number.
  @equipment [
    %{
      "value" => "maxpro",
      "label" => "MaxPRO",
      "load" => @level,
      "min" => 1,
      "max" => 25,
      "step" => 1
    },
    %{
      "value" => "dumbbells",
      "label" => "Adjustable dumbbells",
      "load" => @kg,
      "min" => 10.0,
      "step" => 5.0
    },
    %{
      "value" => "kettlebell",
      "label" => "Adjustable kettlebell",
      "load" => @kg,
      "settings" => [5.0, 11.5, 18.0, 24.5, 31.0, 37.5, 44.0]
    },
    %{"value" => "dip_bars", "label" => "Dip bars", "load" => @bodyweight},
    %{"value" => "pull_up_bar", "label" => "Pull-up bar", "load" => @bodyweight}
  ]

  # The movements, grouped by the equipment they belong to. `activity` is the
  # `WorkoutTypes` value the row is stored under (the exercise name itself is kept in
  # the row's title, exactly as a free-text log keeps the sender's own word), `measure`
  # is what the range counts, and the range is the window worth working in.
  @exercises [
    %{
      "value" => "cable_chest_press",
      "label" => "Cable chest press",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "cable_row",
      "label" => "Seated cable row",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "lat_pulldown",
      "label" => "Lat pulldown",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "cable_shoulder_press",
      "label" => "Cable shoulder press",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "triceps_pushdown",
      "label" => "Triceps pushdown",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15
    },
    %{
      "value" => "cable_curl",
      "label" => "Cable curl",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15
    },
    %{
      "value" => "goblet_squat",
      "label" => "Goblet squat",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "one_arm_row",
      "label" => "One-arm row",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "floor_press",
      "label" => "Floor press",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "split_squat",
      "label" => "Split squat",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "overhead_press",
      "label" => "Standing overhead press",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "kb_swing",
      "label" => "Two-hand swing",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15
    },
    %{
      "value" => "kb_clean_press",
      "label" => "Clean & press",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 8
    },
    %{
      "value" => "kb_row",
      "label" => "Single-arm row",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "kb_romanian_deadlift",
      "label" => "Romanian deadlift",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "kb_halo",
      "label" => "Halo",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12
    },
    %{
      "value" => "dip",
      "label" => "Dip",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10
    },
    %{
      "value" => "l_sit",
      "label" => "L-sit hold",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 15,
      "max" => 45
    },
    %{
      "value" => "supported_knee_raise",
      "label" => "Supported knee raise",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 15
    },
    %{
      "value" => "dip_hold_top",
      "label" => "Dip hold, top",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 15,
      "max" => 45
    },
    %{
      "value" => "pull_up",
      "label" => "Pull-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10
    },
    %{
      "value" => "chin_up",
      "label" => "Chin-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10
    },
    %{
      "value" => "negative_pull_up",
      "label" => "Negative pull-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 3,
      "max" => 6
    },
    %{
      "value" => "hanging_knee_raise",
      "label" => "Hanging knee raise",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 15
    },
    %{
      "value" => "dead_hang",
      "label" => "Dead hang",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 20,
      "max" => 60
    }
  ]

  @doc "The equipment, in the order a picker should offer it, with its load facts."
  @spec equipment() :: [map()]
  def equipment, do: @equipment

  @doc """
  The equipment as `value`/`label` pairs — what a picker draws.

  The load facts are deliberately left out of this list and carried by
  `equipment/0`: a pair is a choice, and `{"load": "kg", "min": 10}` is not something
  anybody presses.
  """
  @spec equipment_options() :: [%{String.t() => String.t()}]
  def equipment_options do
    Enum.map(@equipment, &Map.take(&1, ["value", "label"]))
  end

  @doc "Whether a value names a piece of equipment in this gym."
  @spec equipment_value?(term()) :: boolean()
  def equipment_value?(value), do: Enum.any?(@equipment, &(&1["value"] == value))

  @doc """
  What a number means on a piece of equipment, or `nil` for a name this gym does not have.

  `"kg"`, `"level"`, or `"bodyweight"`.
  """
  @spec load_kind(term()) :: String.t() | nil
  def load_kind(value) do
    case find_equipment(value) do
      nil -> nil
      equipment -> equipment["load"]
    end
  end

  @doc """
  The settings a piece of equipment actually offers, or `nil` for one that takes no
  number.

  A step (`"min"` + `"step"`, and a `"max"` where the device has one) or an explicit
  `"settings"` list, because the two devices differ: the dumbbells step evenly and the
  kettlebell has seven discrete settings. `nil` for the body — there is no ladder for a
  pull-up, and inventing one would be inventing a weight.
  """
  @spec load_settings(term()) :: map() | nil
  def load_settings(value) do
    case find_equipment(value) do
      %{"load" => @bodyweight} -> nil
      %{} = equipment -> Map.drop(equipment, ["value", "label", "load"])
      nil -> nil
    end
  end

  @doc "Every movement in the gym's menu, in the order it should be offered."
  @spec exercises() :: [map()]
  def exercises, do: @exercises

  @doc """
  The movements as wire pairs, carrying what a picker needs to draw and send one:
  the equipment it belongs to, the activity it is stored as, what its range counts,
  and the range itself.
  """
  @spec exercise_options() :: [map()]
  def exercise_options do
    Enum.map(@exercises, fn exercise ->
      %{
        "value" => exercise["value"],
        "label" => exercise["label"],
        "equipment" => exercise["equipment"],
        "activity" => exercise["activity"],
        "measure" => exercise["measure"],
        "min" => exercise["min"],
        "max" => exercise["max"]
      }
    end)
  end

  @doc "The movements a piece of equipment makes possible, in menu order."
  @spec by_equipment(term()) :: [map()]
  def by_equipment(equipment_value) do
    Enum.filter(@exercises, &(&1["equipment"] == equipment_value))
  end

  @doc "One movement by its value, or `nil` for a name this gym does not have."
  @spec exercise(term()) :: map() | nil
  def exercise(value), do: Enum.find(@exercises, &(&1["value"] == value))

  @doc "Whether a value names a movement in this gym's menu."
  @spec known?(term()) :: boolean()
  def known?(value), do: exercise(value) != nil

  @doc """
  The activity a movement is stored as — a `WorkoutTypes` value.

  A row keeps the movement's own name in its `title` and this coarse value in
  `exercise_type`, which is what lets the log report by activity while the menu stays
  detailed. `nil` for a movement this gym does not have.
  """
  @spec activity(term()) :: String.t() | nil
  def activity(value) do
    case exercise(value) do
      nil -> nil
      exercise -> exercise["activity"]
    end
  end

  @doc """
  A movement's range and what it counts, or `nil` for one this gym does not have.

  The range travels with the movement rather than living in a surface: "8–12 reps" is
  the gym's word about the movement, and a view that kept its own copy would be the
  copy this module exists to prevent.
  """
  @spec target(term()) :: %{String.t() => term()} | nil
  def target(value) do
    case exercise(value) do
      nil ->
        nil

      exercise ->
        %{"measure" => exercise["measure"], "min" => exercise["min"], "max" => exercise["max"]}
    end
  end

  defp find_equipment(value), do: Enum.find(@equipment, &(&1["value"] == value))
end

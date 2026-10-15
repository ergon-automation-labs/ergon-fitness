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
                       offers (dumbbells step from 10 to 55 by 5 — they stop there —
                       and the kettlebell has seven discrete settings, so its ladder
                       is a list and not a step).
    * `"level"`      — the device's own resistance level. The MaxPRO dials a
                       PowerClutch, not a weight stack: 25 levels, and the clutch
                       stops there — it locks rather than continuing past 25. No
                       continuous kilogram scale. Recording a "kg" for it would
                       invent a number the device never showed.
    * `"bodyweight"` — the body is the load. A number, when one is recorded, is load
                       *added* (a belt) or *taken away* (an assist), so it is optional
                       and absent means the body alone.

  A surface therefore never has to know which unit to ask for: it reads the kind off
  the wire with the equipment, and a suggestion walks the equipment's own ladder instead
  of adding a "reasonable" kilogram — `BotArmyFitness.Progression`'s job, not this
  module's.

  ## What a movement works, in one vocabulary

  Every movement carries a `"muscles"` map naming what it works, drawn from a fixed list
  of groups (`group_options/0`): `"main"` is what the movement is for, `"also"` is what
  comes along. Free words per movement would have been the fifth vocabulary to disagree —
  "rear delts", "rear shoulders" and "posterior deltoid" are one group spelled three
  ways, and *did this session reach every group* cannot be asked in three vocabularies.

  With every movement tagged, "as much as we can for the machines provided" stops being
  a claim and becomes a read: `uncovered_groups/0` names the groups nothing here reaches
  (currently none) and `groups_without_a_primary_mover/0` names the ones only ever worked
  in a supporting role (currently the lower back and the hip flexors — every hinge loads
  the first and every leg raise loads the second, and no movement here leads with either,
  because a back extension bench and a dedicated hip-flexor movement are things this house
  does not own). The second list is reported rather than closed: padding it would mean
  describing equipment the house does not have.

  ## Nothing here is a score

  The catalog is a menu of what the gym makes possible, with a rep range per movement
  and nothing else. It has no order of merit, no programme, no progression rule and no
  streak — those are the bot's decisions to make from what she actually did, and a
  menu that ranked its own items would be a curriculum, which this is not. The ladder
  above is the piece's own vocabulary (what it can be set to); which rung to reach for
  next is `BotArmyFitness.Progression`'s, read from what she actually lifted.

  ## The equipment is the house's, not the surface's

  Seeding a new piece of kit is an edit to `@equipment` — a fact about the home, not
  user data, and so not a migration. The pairs travel on `fitness.workout.options`
  beside the activities and intensities, and a surface draws them whole or not at all,
  the same contract `WorkoutTypes.type_options/0` has.
  """

  @kg "kg"
  @level "level"
  @bodyweight "bodyweight"

  @measures ["reps", "seconds"]

  # Her counts, not a ladder: 5, 8, 10, 12, 20. A step would have to invent the gaps.
  @rep_choices [5, 8, 10, 12, 20]

  # Float ladders (24.5 kg kettlebell settings) and step arithmetic both need slack.
  @ladder_tolerance 0.01

  # The gym, in the order a picker should offer it. `load` is what a number means;
  # `min`/`step` and `settings` are the ladder the device actually has, and are absent
  # when the load is the body (there is no ladder for a pull-up).
  #
  # The MaxPRO's ladder tops out at 25: the PowerClutch locks at its last level rather
  # than turning further, so 25 is the top of the range and not a round number.
  @equipment [
    # `"note"` is a fact about the house rather than about the device, and it is here
    # because this list is the only place the gym is written down. It rides on
    # `equipment/0` and so reaches anything that talks about the gym — the picker
    # ignores it (it takes value and label), the coach's own words use it. Nothing
    # may read it as a limit: the piece is used from the floor, which is how it is
    # used, not a smaller menu.
    %{
      "value" => "maxpro",
      "label" => "MaxPRO",
      "load" => @level,
      "min" => 1,
      "max" => 25,
      "step" => 1,
      "note" =>
        "a wall attachment exists for it, but it is set up on the floor most of the time, without the bench attachment"
    },
    %{
      "value" => "dumbbells",
      "label" => "Adjustable dumbbells",
      "load" => @kg,
      "min" => 10.0,
      "max" => 55.0,
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

  # The muscle groups this gym can reach, in the order a person would read a body:
  # chest and shoulders, back, arms, middle, legs. A *fixed* vocabulary rather than
  # free words per movement, for the reason five copies of the activity vocabulary had
  # to be retired: "rear delts", "rear shoulders" and "posterior deltoid" are one group
  # spelled three ways, and a coverage question asked in three vocabularies cannot be
  # answered. Every `muscles` entry in `@exercises` below is drawn from this list, and
  # the test suite says so out loud.
  #
  # The list is what the equipment can *reach*, not what a textbook contains: there is
  # no `adductors`, because nothing here isolates them, and there is a `lower_back`,
  # because the hinges load it whether or not anyone presses a button for it.
  @groups [
    %{"value" => "chest", "label" => "chest"},
    %{"value" => "front_delts", "label" => "front shoulders"},
    %{"value" => "side_delts", "label" => "side shoulders"},
    %{"value" => "rear_delts", "label" => "rear shoulders"},
    %{"value" => "lats", "label" => "lats"},
    %{"value" => "upper_back", "label" => "upper back"},
    %{"value" => "traps", "label" => "traps"},
    %{"value" => "lower_back", "label" => "lower back"},
    %{"value" => "biceps", "label" => "biceps"},
    %{"value" => "triceps", "label" => "triceps"},
    %{"value" => "forearms", "label" => "grip and forearms"},
    %{"value" => "abs", "label" => "abs"},
    %{"value" => "obliques", "label" => "obliques"},
    %{"value" => "hip_flexors", "label" => "hip flexors"},
    %{"value" => "glutes", "label" => "glutes"},
    %{"value" => "quads", "label" => "quads"},
    %{"value" => "hamstrings", "label" => "hamstrings"},
    %{"value" => "calves", "label" => "calves"}
  ]

  # The movements, grouped by the equipment they belong to. `activity` is the
  # `WorkoutTypes` value the row is stored under (the exercise name itself is kept in
  # the row's title, exactly as a free-text log keeps the sender's own word), `measure`
  # is what the range counts, and the range is the window worth working in.
  #
  # `muscles` is what the movement works, in the vocabulary of `@groups` above: `main`
  # is what it is for and `also` is what comes along. The two tiers are not a ranking —
  # a movement's helpers are not lesser movements, they are the same movement seen from
  # the other side — but they answer different questions: "which movements would I press
  # for my side shoulders" reads `main`, and "did today's session reach my triceps at all"
  # reads both. Nothing here is a score, and nothing here is a programme: this is what
  # the movement *works*, never how much of it is worth doing.
  # The broad areas a body is read in, for a screen that would otherwise draw eighteen
  # chips at once. Each group above belongs to exactly one area — this list is a
  # partition of `@groups`, not a second opinion about the muscles, and a test says so
  # out loud. `chest` and `shoulders` are kept apart because a press and a raise are
  # different questions; `traps` sits with the back because a shrug is a pull. Nothing
  # here is a programme and nothing here is a muscle: it is how many words a person
  # wants on one row before a body stops being a menu.
  @areas [
    %{"value" => "chest", "label" => "chest", "groups" => ["chest"]},
    %{
      "value" => "shoulders",
      "label" => "shoulders",
      "groups" => ["front_delts", "side_delts", "rear_delts"]
    },
    %{
      "value" => "back",
      "label" => "back",
      "groups" => ["lats", "upper_back", "traps", "lower_back"]
    },
    %{"value" => "arms", "label" => "arms", "groups" => ["biceps", "triceps", "forearms"]},
    %{"value" => "core", "label" => "core", "groups" => ["abs", "obliques", "hip_flexors"]},
    %{
      "value" => "legs",
      "label" => "legs",
      "groups" => ["glutes", "quads", "hamstrings", "calves"]
    }
  ]

  @exercises [
    %{
      "value" => "cable_chest_press",
      "label" => "Cable chest press",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["chest"], "also" => ["front_delts", "triceps"]}
    },
    %{
      "value" => "cable_fly",
      "label" => "Cable fly",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["chest"], "also" => ["front_delts"]}
    },
    %{
      "value" => "cable_shoulder_press",
      "label" => "Cable shoulder press",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["front_delts"], "also" => ["triceps", "side_delts"]}
    },
    %{
      "value" => "cable_lateral_raise",
      "label" => "Cable lateral raise",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["side_delts"], "also" => ["traps"]}
    },
    %{
      "value" => "cable_upright_row",
      "label" => "Cable upright row",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["side_delts"], "also" => ["traps", "upper_back"]}
    },
    %{
      "value" => "triceps_pushdown",
      "label" => "Triceps pushdown",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["triceps"], "also" => []}
    },
    %{
      "value" => "cable_overhead_triceps",
      "label" => "Overhead triceps extension",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["triceps"], "also" => []}
    },
    %{
      "value" => "lat_pulldown",
      "label" => "Lat pulldown",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["lats"], "also" => ["upper_back", "biceps"]}
    },
    %{
      "value" => "cable_row",
      "label" => "Seated cable row",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["upper_back", "lats"], "also" => ["biceps", "rear_delts"]}
    },
    %{
      "value" => "cable_face_pull",
      "label" => "Cable face pull",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 12,
      "max" => 20,
      "muscles" => %{"main" => ["rear_delts"], "also" => ["upper_back", "traps"]}
    },
    %{
      "value" => "cable_reverse_fly",
      "label" => "Cable reverse fly",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["rear_delts"], "also" => ["upper_back"]}
    },
    %{
      "value" => "cable_shrug",
      "label" => "Cable shrug",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["traps"], "also" => ["forearms"]}
    },
    %{
      "value" => "cable_curl",
      "label" => "Cable curl",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["biceps"], "also" => ["forearms"]}
    },
    %{
      "value" => "cable_crunch",
      "label" => "Cable crunch",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["abs"], "also" => ["obliques"]}
    },
    %{
      "value" => "cable_woodchop",
      "label" => "Cable woodchop",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["obliques"], "also" => ["abs"]}
    },
    %{
      "value" => "cable_pull_through",
      "label" => "Cable pull-through",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["glutes"], "also" => ["hamstrings", "lower_back"]}
    },
    %{
      "value" => "cable_glute_kickback",
      "label" => "Cable glute kickback",
      "equipment" => "maxpro",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["glutes"], "also" => ["hamstrings"]}
    },
    %{
      "value" => "goblet_squat",
      "label" => "Goblet squat",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["quads", "glutes"], "also" => ["abs", "upper_back"]}
    },
    %{
      "value" => "split_squat",
      "label" => "Split squat",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["quads", "glutes"], "also" => ["hamstrings", "abs"]}
    },
    %{
      "value" => "bulgarian_split_squat",
      "label" => "Bulgarian split squat",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["quads", "glutes"], "also" => ["hamstrings", "abs"]}
    },
    %{
      "value" => "reverse_lunge",
      "label" => "Reverse lunge",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["quads", "glutes"], "also" => ["hamstrings", "abs"]}
    },
    %{
      "value" => "calf_raise",
      "label" => "Standing calf raise",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 12,
      "max" => 20,
      "muscles" => %{"main" => ["calves"], "also" => []}
    },
    %{
      "value" => "floor_press",
      "label" => "Floor press",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["chest"], "also" => ["triceps", "front_delts"]}
    },
    %{
      "value" => "overhead_press",
      "label" => "Standing overhead press",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["front_delts"], "also" => ["triceps", "side_delts", "abs"]}
    },
    %{
      "value" => "one_arm_row",
      "label" => "One-arm row",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["lats", "upper_back"], "also" => ["biceps", "forearms"]}
    },
    %{
      "value" => "lateral_raise",
      "label" => "Lateral raise",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["side_delts"], "also" => ["traps"]}
    },
    %{
      "value" => "rear_delt_fly",
      "label" => "Bent-over rear delt fly",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["rear_delts"], "also" => ["upper_back"]}
    },
    %{
      "value" => "dumbbell_shrug",
      "label" => "Dumbbell shrug",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["traps"], "also" => ["forearms"]}
    },
    %{
      "value" => "dumbbell_curl",
      "label" => "Dumbbell curl",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["biceps"], "also" => ["forearms"]}
    },
    %{
      "value" => "hammer_curl",
      "label" => "Hammer curl",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["biceps"], "also" => ["forearms"]}
    },
    %{
      "value" => "reverse_curl",
      "label" => "Reverse curl",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["forearms"], "also" => ["biceps"]}
    },
    %{
      "value" => "dumbbell_overhead_triceps",
      "label" => "Seated overhead triceps extension",
      "equipment" => "dumbbells",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{"main" => ["triceps"], "also" => []}
    },
    %{
      "value" => "kb_swing",
      "label" => "Two-hand swing",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 10,
      "max" => 15,
      "muscles" => %{
        "main" => ["glutes", "hamstrings"],
        "also" => ["lower_back", "abs", "forearms"]
      }
    },
    %{
      "value" => "kb_clean_press",
      "label" => "Clean & press",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 8,
      "muscles" => %{
        "main" => ["front_delts"],
        "also" => ["glutes", "quads", "abs", "forearms"]
      }
    },
    %{
      "value" => "kb_row",
      "label" => "Single-arm row",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["lats", "upper_back"], "also" => ["biceps", "forearms"]}
    },
    %{
      "value" => "kb_romanian_deadlift",
      "label" => "Romanian deadlift",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{
        "main" => ["hamstrings", "glutes"],
        "also" => ["lower_back", "forearms"]
      }
    },
    %{
      "value" => "kb_halo",
      "label" => "Halo",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["side_delts"], "also" => ["abs"]}
    },
    %{
      "value" => "kb_suitcase_carry",
      "label" => "Suitcase carry",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 20,
      "max" => 45,
      "muscles" => %{"main" => ["obliques"], "also" => ["forearms", "abs", "traps"]}
    },
    %{
      "value" => "kb_turkish_get_up",
      "label" => "Turkish get-up",
      "equipment" => "kettlebell",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 3,
      "max" => 6,
      "muscles" => %{
        "main" => ["abs", "side_delts"],
        "also" => ["glutes", "quads", "forearms", "upper_back"]
      }
    },
    %{
      "value" => "dip",
      "label" => "Dip",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10,
      "muscles" => %{"main" => ["chest", "triceps"], "also" => ["front_delts"]}
    },
    %{
      "value" => "dip_hold_top",
      "label" => "Dip hold, top",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 15,
      "max" => 45,
      "muscles" => %{"main" => ["chest", "triceps"], "also" => ["front_delts"]}
    },
    %{
      "value" => "dip_bar_push_up",
      "label" => "Dip-bar push-up",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["chest"], "also" => ["triceps", "front_delts"]}
    },
    %{
      "value" => "inverted_row",
      "label" => "Inverted row",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["upper_back"], "also" => ["lats", "biceps", "forearms"]}
    },
    %{
      "value" => "supported_knee_raise",
      "label" => "Supported knee raise",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 15,
      "muscles" => %{"main" => ["abs"], "also" => ["hip_flexors"]}
    },
    %{
      "value" => "l_sit",
      "label" => "L-sit hold",
      "equipment" => "dip_bars",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 15,
      "max" => 45,
      "muscles" => %{"main" => ["abs"], "also" => ["hip_flexors", "quads", "triceps"]}
    },
    %{
      "value" => "pull_up",
      "label" => "Pull-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10,
      "muscles" => %{
        "main" => ["lats", "upper_back"],
        "also" => ["biceps", "forearms", "abs"]
      }
    },
    %{
      "value" => "chin_up",
      "label" => "Chin-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 5,
      "max" => 10,
      "muscles" => %{"main" => ["biceps", "lats"], "also" => ["upper_back", "forearms"]}
    },
    %{
      "value" => "negative_pull_up",
      "label" => "Negative pull-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 3,
      "max" => 6,
      "muscles" => %{"main" => ["lats", "upper_back"], "also" => ["biceps", "forearms"]}
    },
    %{
      "value" => "scapular_pull_up",
      "label" => "Scapular pull-up",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 12,
      "muscles" => %{"main" => ["lats"], "also" => ["upper_back", "traps", "forearms"]}
    },
    %{
      "value" => "hanging_knee_raise",
      "label" => "Hanging knee raise",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 15,
      "muscles" => %{"main" => ["abs"], "also" => ["hip_flexors", "forearms"]}
    },
    %{
      "value" => "hanging_leg_raise",
      "label" => "Hanging leg raise",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "reps",
      "min" => 8,
      "max" => 15,
      "muscles" => %{"main" => ["abs"], "also" => ["hip_flexors", "forearms"]}
    },
    %{
      "value" => "dead_hang",
      "label" => "Dead hang",
      "equipment" => "pull_up_bar",
      "activity" => "strength",
      "measure" => "seconds",
      "min" => 20,
      "max" => 60,
      "muscles" => %{"main" => ["forearms"], "also" => ["lats", "upper_back"]}
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
      %{} = equipment -> Map.take(equipment, ["min", "max", "step", "settings"])
      nil -> nil
    end
  end

  @doc """
  The muscle groups this gym can reach, as `value`/`label` pairs.

  A fixed vocabulary and not free words, because "rear delts", "rear shoulders" and
  "posterior deltoid" are one group spelled three ways, and a question asked in three
  vocabularies — *did this session reach every group* — cannot be answered. The list is
  what the four pieces can reach rather than what a textbook contains: no `adductors`,
  because nothing here isolates them, and a `lower_back`, because the hinges load it.
  """
  @spec group_options() :: [%{String.t() => String.t()}]
  def group_options, do: Enum.map(@groups, &Map.take(&1, ["value", "label"]))

  @doc "The muscle-group values, in reading order."
  @spec groups() :: [String.t()]
  def groups, do: Enum.map(@groups, & &1["value"])

  @doc "Whether a value names a muscle group in this vocabulary."
  @spec group_value?(term()) :: boolean()
  def group_value?(value), do: Enum.any?(@groups, &(&1["value"] == value))

  @doc "The human words for a group, or `nil` for a value outside this vocabulary."
  @spec group_label(term()) :: String.t() | nil
  def group_label(value) do
    case Enum.find(@groups, &(&1["value"] == value)) do
      nil -> nil
      group -> group["label"]
    end
  end

  @doc "Every movement in the gym's menu, in the order it should be offered."
  @spec exercises() :: [map()]
  def exercises, do: @exercises

  @doc """
  The broad areas a body is read in, each carrying the groups it covers.

  A screen that would otherwise draw eighteen group chips draws these instead. The
  groups stay the honest vocabulary — a movement works groups, never areas — and this
  list only says which groups sit near one another. Each area is sent whole
  (`value`, `label`, `groups`), so a surface can filter the menu by area without
  holding a copy of the mapping: the bot is what says which groups an area covers.
  """
  @spec area_options() :: [map()]
  def area_options, do: @areas

  @doc "The area values, in reading order."
  @spec areas() :: [String.t()]
  def areas, do: Enum.map(@areas, & &1["value"])

  @doc "Whether a value names an area in this vocabulary."
  @spec area_value?(term()) :: boolean()
  def area_value?(value), do: Enum.any?(@areas, &(&1["value"] == value))

  @doc "The human words for an area, or `nil` for a value outside this vocabulary."
  @spec area_label(term()) :: String.t() | nil
  def area_label(value) do
    case Enum.find(@areas, &(&1["value"] == value)) do
      nil -> nil
      area -> area["label"]
    end
  end

  @doc "The group values an area covers, or `nil` for a value outside this vocabulary."
  @spec groups_for_area(term()) :: [String.t()] | nil
  def groups_for_area(value) do
    case Enum.find(@areas, &(&1["value"] == value)) do
      nil -> nil
      area -> area["groups"]
    end
  end

  @doc "The area a group belongs to, or `nil` for a group this vocabulary does not have."
  @spec area_for_group(term()) :: String.t() | nil
  def area_for_group(group) do
    case Enum.find(@areas, &(group in &1["groups"])) do
      nil -> nil
      area -> area["value"]
    end
  end

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
        "max" => exercise["max"],
        "muscles" => exercise["muscles"]
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

  @doc """
  What a movement works: `%{"main" => [...], "also" => [...]}`, or `nil` for a name
  this gym does not have.

  `main` is what the movement is for; `also` is what comes along. The two answer
  different questions — *which movements would I press for my side shoulders* reads
  `main`, and *did today reach my triceps at all* reads both — and neither is a score.
  """
  @spec muscles_for(term()) :: %{String.t() => [String.t()]} | nil
  def muscles_for(value) do
    case exercise(value) do
      nil -> nil
      exercise -> exercise["muscles"]
    end
  end

  @doc """
  Whether a movement works a muscle group, leading or helping.

  `false` for a movement or a group this gym does not have. "Not in this vocabulary"
  and "not worked" are the same answer to this question and are deliberately not
  distinguished: a caller that has a group value it did not get from
  `group_options/0` has a bug, not a movement to look up.
  """
  @spec works?(term(), term()) :: boolean()
  def works?(movement, group) do
    case muscles_for(movement) do
      nil -> false
      muscles -> group in muscles["main"] or group in muscles["also"]
    end
  end

  @doc "The movements that lead with a group, in menu order."
  @spec exercises_for_group(term()) :: [map()]
  def exercises_for_group(group) do
    Enum.filter(@exercises, &(group in &1["muscles"]["main"]))
  end

  @doc """
  The groups no movement in this gym reaches at all — this list is empty, and the test
  suite is what says so.

  "As much as we can for the machines provided" is a claim, and this is the receipt: a
  movement was added for every group, and what remains unwritten here is what the four
  pieces genuinely cannot do.
  """
  @spec uncovered_groups() :: [String.t()]
  def uncovered_groups do
    Enum.reject(groups(), fn group -> Enum.any?(@exercises, &works?(&1["value"], group)) end)
  end

  @doc """
  The groups no movement *leads* with, though something may help.

  Reported rather than fixed by inventing a movement: a lower back is loaded by every
  hinge this gym has and is nobody's prime mover without a back extension bench, which
  is not here. A gym that padded this list would be describing equipment it does not
  own.
  """
  @spec groups_without_a_primary_mover() :: [String.t()]
  def groups_without_a_primary_mover do
    Enum.reject(groups(), fn group -> exercises_for_group(group) != [] end)
  end

  @doc """
  The counts she actually presses, from the person whose gym this is.

  A rep range is the gym's opinion about a movement ("8-12 is the window worth
  working in"); these are the counts a press may name. They are separate facts and
  live in separate places for that reason: a range is what the bot suggests from, a
  choice is what a card draws. The list is hers and not a ladder — she gave
  `5, 8, 10, 12, 20`, which is not an arithmetic sequence, so it is a list and not a
  `min`/`step`.
  """
  @spec rep_choices() :: [pos_integer()]
  def rep_choices, do: @rep_choices

  @doc "What a movement's range can count. The values `measure` may take."
  @spec measures() :: [String.t()]
  def measures, do: @measures

  @doc "What a number on a piece of equipment can mean. The values `load` may take."
  @spec load_kinds() :: [String.t()]
  def load_kinds, do: [@kg, @level, @bodyweight]

  @doc "The piece of equipment a movement belongs to, or `nil` for a name outside this gym."
  @spec equipment_for(term()) :: String.t() | nil
  def equipment_for(value) do
    case exercise(value) do
      nil -> nil
      exercise -> exercise["equipment"]
    end
  end

  @doc """
  Whether a number is one this piece of equipment can actually show.

  The ladder is the device's own fact: the kettlebell has seven discrete settings, the
  dumbbells step from 10 to 55, the MaxPRO dials 1 to 25. A number that is not on the
  ladder is not a weight she could have selected, so this is a refusal and not a
  round — rounding 23 kg onto a kettlebell that has no 23 would record a set that
  never happened. The body takes any number: a bodyweight movement's number is load
  added (a belt) or taken away (an assist), which is why it may be negative.

  `false` for a piece this gym does not have, and for a number that is not a number.
  """
  @spec load_allowed?(term(), term()) :: boolean()
  def load_allowed?(equipment_value, value) do
    case find_equipment(equipment_value) do
      nil -> false
      %{"load" => @bodyweight} -> is_number(value)
      equipment -> on_ladder?(equipment, value)
    end
  end

  defp on_ladder?(%{"settings" => settings}, value) when is_number(value) do
    Enum.any?(settings, &within?(&1, value))
  end

  defp on_ladder?(%{"min" => min, "step" => step} = equipment, value) when is_number(value) do
    top = Map.get(equipment, "max")
    above_min? = value >= min - @ladder_tolerance
    within_top? = is_nil(top) or value <= top + @ladder_tolerance
    on_step? = integral?((value - min) / step)
    above_min? and within_top? and on_step?
  end

  defp on_ladder?(_equipment, _value), do: false

  # Float ladders mean 24.5 is 24.5 plus or minus the last bit, and a step count is
  # never exactly integral. Both comparisons need a tolerance or the kettlebell's own
  # settings would be refused.
  defp within?(setting, value), do: abs(setting - value) <= @ladder_tolerance

  defp integral?(steps) do
    abs(steps - Float.round(steps)) <= @ladder_tolerance
  end

  defp find_equipment(value), do: Enum.find(@equipment, &(&1["value"] == value))
end

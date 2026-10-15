defmodule BotArmyFitness.ExerciseCatalogTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.ExerciseCatalog
  alias BotArmyFitness.Handlers.WorkoutHandler
  alias BotArmyFitness.WorkoutTypes

  # Same workspace contract as the WorkoutTypes parity test: the schemas repo is a
  # sibling, provisioned by scripts/install_workspace.sh, and a guard that silently
  # skips when it cannot find the file it guards is not a guard.
  @schema_path Path.expand("../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)

  describe "the equipment" do
    test "values are unique, lower-case, and non-empty" do
      values = Enum.map(ExerciseCatalog.equipment(), & &1["value"])

      assert values == Enum.uniq(values)
      refute Enum.any?(values, &(&1 == ""))
      assert Enum.all?(values, &(&1 == String.downcase(&1)))
    end

    test "every piece has a label that is not the raw value" do
      for equipment <- ExerciseCatalog.equipment() do
        label = equipment["label"]

        assert is_binary(label) and label != ""
        assert label != equipment["value"]
        assert String.upcase(String.first(label)) == String.first(label)
      end
    end

    test "every piece declares a load kind the bot understands" do
      for equipment <- ExerciseCatalog.equipment() do
        assert equipment["load"] in ["kg", "level", "bodyweight"],
               "#{equipment["value"]} has no load kind"
      end
    end

    test "a piece that takes a number says what its ladder is" do
      # The load kind is the promise; the ladder is the arithmetic a suggestion is
      # allowed to walk. Without it a coach would have to invent a sensible
      # kilogram, which is the thing this catalog exists to prevent.
      for equipment <- ExerciseCatalog.equipment(), equipment["load"] != "bodyweight" do
        settings = ExerciseCatalog.load_settings(equipment["value"])

        assert is_map(settings) and map_size(settings) > 0,
               "#{equipment["value"]} takes a number but offers no settings"
      end
    end

    test "the body carries no ladder at all" do
      for equipment <- ExerciseCatalog.equipment(), equipment["load"] == "bodyweight" do
        assert ExerciseCatalog.load_settings(equipment["value"]) == nil
      end
    end

    test "the dumbbells start at 10, step by 5, and stop at 55" do
      # 55 kg is the top of this rack (the pair is adjustable, each dumbbell carries
      # the number). Without the top the ladder would grow past what the rack can
      # make, which is the same lie as a kettlebell setting that does not exist.
      assert ExerciseCatalog.load_settings("dumbbells") == %{
               "min" => 10.0,
               "max" => 55.0,
               "step" => 5.0
             }
    end

    test "the kettlebell offers its seven real settings, not a invented step" do
      # A VEVER adjustable kettlebell. The settings are not evenly spaced, so a
      # step would put the suggestion on a weight the device cannot make.
      assert ExerciseCatalog.load_settings("kettlebell") == %{
               "settings" => [5.0, 11.5, 18.0, 24.5, 31.0, 37.5, 44.0]
             }
    end

    test "the MaxPRO records a level, not a kilogram" do
      # It dials a PowerClutch (25 levels), not a weight stack, and the clutch locks at
      # its last level rather than turning further — so 25 is the top. Recording kg
      # here would be a number the device never showed her.
      assert ExerciseCatalog.load_kind("maxpro") == "level"
      assert ExerciseCatalog.load_settings("maxpro") == %{"min" => 1, "max" => 25, "step" => 1}
    end

    test "the load kinds land on the pieces the house actually has" do
      assert ExerciseCatalog.load_kind("dumbbells") == "kg"
      assert ExerciseCatalog.load_kind("kettlebell") == "kg"
      assert ExerciseCatalog.load_kind("dip_bars") == "bodyweight"
      assert ExerciseCatalog.load_kind("pull_up_bar") == "bodyweight"
    end

    test "a name that is not in the gym has no load kind" do
      assert ExerciseCatalog.load_kind("barbell") == nil
      assert ExerciseCatalog.load_settings("barbell") == nil
      refute ExerciseCatalog.equipment_value?("barbell")
    end
  end

  describe "the movements" do
    test "values are unique, lower-case, and non-empty" do
      values = Enum.map(ExerciseCatalog.exercises(), & &1["value"])

      assert values == Enum.uniq(values)
      refute Enum.any?(values, &(&1 == ""))
      assert Enum.all?(values, &(&1 == String.downcase(&1)))
    end

    test "every movement belongs to a piece of equipment in the gym" do
      for exercise <- ExerciseCatalog.exercises() do
        assert ExerciseCatalog.equipment_value?(exercise["equipment"]),
               "#{exercise["value"]} names equipment this gym does not have"
      end
    end

    test "every movement is stored under an activity the bot accepts" do
      # The row keeps the movement's own name in `title` and this coarse value in
      # `exercise_type`, so a value the vocabulary does not store would be a write
      # the changeset refuses after the log already looked accepted.
      for exercise <- ExerciseCatalog.exercises() do
        assert exercise["activity"] in WorkoutTypes.values(),
               "#{exercise["value"]} would be stored as #{exercise["activity"]}"
      end
    end

    test "every movement counts reps or seconds, and its range is the right way round" do
      for exercise <- ExerciseCatalog.exercises() do
        assert exercise["measure"] in ["reps", "seconds"]
        assert is_integer(exercise["min"]) and is_integer(exercise["max"])
        assert exercise["min"] >= 1

        assert exercise["min"] < exercise["max"],
               "#{exercise["value"]} has an empty range"
      end
    end

    test "every movement works at least one group, and none of them is a word of its own" do
      for exercise <- ExerciseCatalog.exercises() do
        muscles = ExerciseCatalog.muscles_for(exercise["value"])

        assert is_map(muscles), "#{exercise["value"]} says nothing about what it works"
        assert is_list(muscles["main"]) and is_list(muscles["also"])
        assert muscles["main"] != [], "#{exercise["value"]} leads with nothing"

        for group <- muscles["main"] ++ muscles["also"] do
          assert ExerciseCatalog.group_value?(group),
                 "#{exercise["value"]} works #{group}, which is not in the vocabulary"
        end

        assert muscles["main"] == Enum.uniq(muscles["main"])
        assert muscles["also"] == Enum.uniq(muscles["also"])
        assert Enum.all?(muscles["also"], &(&1 not in muscles["main"]))
      end
    end

    test "no group is left unreached by any movement in the gym" do
      # "As much as we can for the machines provided" is a claim about four pieces of
      # equipment. This is the receipt, and it is empty: every group in the vocabulary has
      # at least one movement here that works it. A group that appeared in this list would
      # be a group the house cannot train, and the fix would be an edit to `@exercises` or
      # an honest word in the docs — never a movement that cannot be performed.
      assert ExerciseCatalog.uncovered_groups() == []
    end

    test "the groups no movement leads with are named, not padded away" do
      # The lower back and the hip flexors are worked here and never led with: every hinge
      # loads the first, every leg raise the second, and a movement that leads with either
      # would need a back-extension bench or a hip-flexor machine, which this house does
      # not own. Adding a movement to empty this list would describe equipment that is not
      # here, so the list is reported instead.
      assert ExerciseCatalog.groups_without_a_primary_mover() == ["lower_back", "hip_flexors"]

      assert ExerciseCatalog.exercises_for_group("lower_back") == []

      assert ExerciseCatalog.exercises_for_group("calves") |> Enum.map(& &1["value"]) ==
               ["calf_raise"]
    end

    test "the vocabulary is one list, and it reads like a body" do
      values = ExerciseCatalog.groups()

      assert ExerciseCatalog.group_options() |> Enum.map(& &1["value"]) == values
      assert values == Enum.uniq(values)
      assert Enum.all?(values, &(&1 == String.downcase(&1)))

      for pair <- ExerciseCatalog.group_options() do
        assert is_binary(pair["label"]) and pair["label"] != ""
        assert pair["label"] == String.downcase(pair["label"])
      end

      assert ExerciseCatalog.group_label("rear_delts") == "rear shoulders"
      assert ExerciseCatalog.group_label("not_a_group") == nil
      refute ExerciseCatalog.group_value?("rear_delts ")
    end

    test "what a movement works can be asked either way round" do
      assert ExerciseCatalog.muscles_for("cable_chest_press") == %{
               "main" => ["chest"],
               "also" => ["front_delts", "triceps"]
             }

      assert ExerciseCatalog.muscles_for("not_a_movement") == nil

      assert ExerciseCatalog.works?("cable_chest_press", "chest")
      assert ExerciseCatalog.works?("cable_chest_press", "triceps")
      refute ExerciseCatalog.works?("cable_chest_press", "lats")
      refute ExerciseCatalog.works?("not_a_movement", "chest")
      refute ExerciseCatalog.works?("cable_chest_press", "not_a_group")

      assert ExerciseCatalog.exercises_for_group("chest") |> Enum.map(& &1["value"]) ==
               ~w(cable_chest_press cable_fly floor_press dip dip_hold_top dip_bar_push_up)
    end

    test "the broad areas partition the groups, with none left out and none counted twice" do
      # The area layer exists so a screen draws six chips instead of eighteen. It is a
      # partition, not a second vocabulary: every group sits in exactly one area, so
      # filtering the menu by area can never miss a movement or double it.
      covered = Enum.flat_map(ExerciseCatalog.area_options(), & &1["groups"])

      assert Enum.sort(covered) == Enum.sort(ExerciseCatalog.groups())
      assert covered == Enum.uniq(covered)

      for pair <- ExerciseCatalog.area_options() do
        assert Map.keys(pair) |> Enum.sort() == ["groups", "label", "value"]
        assert pair["label"] == String.downcase(pair["label"])
        assert pair["groups"] != []
      end
    end

    test "the area covering a group can be asked either way round" do
      assert ExerciseCatalog.area_for_group("rear_delts") == "shoulders"
      assert ExerciseCatalog.area_for_group("traps") == "back"
      assert ExerciseCatalog.area_for_group("hip_flexors") == "core"
      assert ExerciseCatalog.area_for_group("not_a_group") == nil

      assert ExerciseCatalog.groups_for_area("legs") ==
               ["glutes", "quads", "hamstrings", "calves"]

      assert ExerciseCatalog.groups_for_area("not_an_area") == nil
      assert ExerciseCatalog.area_label("chest") == "chest"
      assert ExerciseCatalog.area_label("not_an_area") == nil
      refute ExerciseCatalog.area_value?("chest ")
      assert ExerciseCatalog.area_value?("core")
    end

    test "the options reply carries the areas and each movement's muscles" do
      # "Which movements for my back" has to be answerable from the reply alone: the
      # bot sends the areas and the groups under each, and the muscles on every
      # movement, so a surface holds no copy of either.
      reply = WorkoutHandler.handle_options(%{}) |> Jason.decode!()

      assert reply["data"]["areas"] == ExerciseCatalog.area_options()

      press = reply["data"]["exercises"] |> Enum.find(&(&1["value"] == "cable_chest_press"))

      assert press["muscles"] == %{
               "main" => ["chest"],
               "also" => ["front_delts", "triceps"]
             }
    end

    test "every movement value the vocabulary names exists, and the gym has fifty-two" do
      assert length(ExerciseCatalog.exercises()) == 52

      counts =
        ExerciseCatalog.equipment()
        |> Map.new(&{&1["value"], length(ExerciseCatalog.by_equipment(&1["value"]))})

      assert counts == %{
               "maxpro" => 17,
               "dumbbells" => 15,
               "kettlebell" => 7,
               "dip_bars" => 6,
               "pull_up_bar" => 7
             }
    end

    test "every piece makes at least three movements possible" do
      for equipment <- ExerciseCatalog.equipment() do
        movements = ExerciseCatalog.by_equipment(equipment["value"])

        assert length(movements) >= 3,
               "#{equipment["value"]} is in the gym but offers #{length(movements)} movements"
      end
    end

    test "the menu is longer than a screen, and bounding it is the method's job" do
      # This test used to assert that no piece offers more than six movements, because a
      # picker that drew a piece's whole menu ungrouped became a nineteen-item list. The
      # menu has since grown on purpose — the gym was asked for enough movements to work
      # every muscle group it can reach — so the bound moved to where a screen reads *one*
      # list: `BotArmyFitness.Coach`'s sessions, six slots each. Keeping the old number
      # here would have been a lie about the menu, and a second copy of the method's own
      # bound, which `coach_test.exs` already asserts.
      assert length(ExerciseCatalog.exercises()) >= 50
    end

    test "the menu names the equipment that is actually here" do
      assert ExerciseCatalog.equipment() |> Enum.map(& &1["value"]) ==
               ~w(maxpro dumbbells kettlebell dip_bars pull_up_bar)

      assert WorkoutTypes.values() |> Enum.member?("strength")
    end

    test "a movement carries its range with it" do
      assert ExerciseCatalog.target("l_sit") == %{
               "measure" => "seconds",
               "min" => 15,
               "max" => 45
             }

      assert ExerciseCatalog.target("goblet_squat")["measure"] == "reps"
      assert ExerciseCatalog.target("not_a_movement") == nil
    end

    test "a movement's activity is the one its row is stored as" do
      assert ExerciseCatalog.activity("goblet_squat") == "strength"
      assert ExerciseCatalog.activity("not_a_movement") == nil
      assert ExerciseCatalog.known?("kb_swing")
      refute ExerciseCatalog.known?("clean_and_jerk")
      assert ExerciseCatalog.exercise("kb_swing")["equipment"] == "kettlebell"
      assert ExerciseCatalog.exercise("clean_and_jerk") == nil
    end
  end

  describe "what the picker receives" do
    test "the equipment options are exactly value and label" do
      for pair <- ExerciseCatalog.equipment_options() do
        assert Map.keys(pair) |> Enum.sort() == ["label", "value"]
      end

      assert ExerciseCatalog.equipment_options() ==
               Enum.map(ExerciseCatalog.equipment(), &Map.take(&1, ["value", "label"]))
    end

    test "an exercise option carries everything a picker sends with it" do
      for option <- ExerciseCatalog.exercise_options() do
        assert Map.keys(option) |> Enum.sort() ==
                 ~w(activity equipment label max measure min muscles value)
      end
    end

    test "the options reply carries the gym beside the activities" do
      reply = WorkoutHandler.handle_options(%{}) |> Jason.decode!()

      assert reply["data"]["equipment"] == ExerciseCatalog.equipment()
      assert reply["data"]["exercises"] == ExerciseCatalog.exercise_options()
      assert reply["data"]["areas"] == ExerciseCatalog.area_options()
      assert reply["data"]["workout_types"] == WorkoutTypes.type_options()
    end

    test "the panel can find a movement's equipment from the reply alone" do
      # The panel holds no list: it draws the equipment pairs, then the movements
      # whose `equipment` matches the one she pressed.
      reply = WorkoutHandler.handle_options(%{}) |> Jason.decode!()

      kettlebells =
        reply["data"]["exercises"] |> Enum.filter(&(&1["equipment"] == "kettlebell"))

      assert kettlebells != []
      assert Enum.all?(kettlebells, &(&1["activity"] in WorkoutTypes.values()))

      equipment = reply["data"]["equipment"] |> Enum.map(& &1["value"])
      assert Enum.all?(reply["data"]["exercises"], &(&1["equipment"] in equipment))
    end
  end

  describe "parity with the published schema" do
    test "the reply's equipment enum matches the gym" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["properties"]["equipment"]["items"]["properties"][
               "value"
             ]["enum"] == ExerciseCatalog.equipment() |> Enum.map(& &1["value"])
    end

    test "the reply's exercise enum matches the menu" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["properties"]["exercises"]["items"]["properties"][
               "value"
             ]["enum"] == ExerciseCatalog.exercises() |> Enum.map(& &1["value"])
    end

    test "the reply's activity enum stays the vocabulary's stored values" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["properties"]["exercises"]["items"]["properties"][
               "activity"
             ]["enum"] == WorkoutTypes.values()
    end

    test "the reply's area enum matches the broad layer" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["properties"]["areas"]["items"]["properties"]["value"][
               "enum"
             ] == ExerciseCatalog.areas()
    end

    test "the reply requires the gym it always sends" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["required"] |> Enum.sort() ==
               ~w(equipment exercises intensities rep_choices workout_types)
    end

    test "there is an example proving each load kind is exercisable" do
      path = Path.join(@schema_path, "../examples/fitness.workout.options.reply.json")
      body = path |> File.read!() |> Jason.decode!()
      loads = body["data"]["equipment"] |> Enum.map(& &1["load"]) |> Enum.uniq()

      assert Enum.sort(loads) == ["bodyweight", "kg", "level"]
    end
  end

  describe "the counts she presses" do
    test "are hers, and are a list rather than a step" do
      # She gave five counts: 5, 8, 10, 12, 20. A step would have to invent the gaps
      # (5, 10, 15, 20 is a different gym), so the list travels as a list.
      assert ExerciseCatalog.rep_choices() == [5, 8, 10, 12, 20]

      gaps =
        ExerciseCatalog.rep_choices()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)
        |> Enum.uniq()

      assert length(gaps) > 1, "the counts became an arithmetic ladder: #{inspect(gaps)}"
    end

    test "are published on the options reply, so no surface keeps its own copy" do
      reply =
        BotArmyFitness.Handlers.WorkoutHandler.handle_options()
        |> Jason.decode!()

      assert reply["data"]["rep_choices"] == [5, 8, 10, 12, 20]
    end

    test "every movement's measure is one the reply schema allows" do
      assert ExerciseCatalog.measures() == ["reps", "seconds"]
      assert ExerciseCatalog.load_kinds() == ["kg", "level", "bodyweight"]

      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["properties"]["exercises"]["items"]["properties"][
               "measure"
             ]["enum"] == ExerciseCatalog.measures()
    end
  end

  describe "the ladder a number has to be on" do
    test "the dumbbells take anything they can be set to, and nothing else" do
      assert ExerciseCatalog.load_allowed?("dumbbells", 10)
      assert ExerciseCatalog.load_allowed?("dumbbells", 25)
      assert ExerciseCatalog.load_allowed?("dumbbells", 55)

      refute ExerciseCatalog.load_allowed?("dumbbells", 9)
      refute ExerciseCatalog.load_allowed?("dumbbells", 24.5)
      refute ExerciseCatalog.load_allowed?("dumbbells", 60)
    end

    test "the kettlebell takes its seven settings, not the numbers between them" do
      for setting <- [5.0, 11.5, 18.0, 24.5, 31.0, 37.5, 44.0] do
        assert ExerciseCatalog.load_allowed?("kettlebell", setting),
               "#{setting} kg is a setting of this kettlebell"
      end

      refute ExerciseCatalog.load_allowed?("kettlebell", 24)
      refute ExerciseCatalog.load_allowed?("kettlebell", 50)
    end

    test "the MaxPRO dials 1 to 25 and locks there" do
      assert ExerciseCatalog.load_allowed?("maxpro", 1)
      assert ExerciseCatalog.load_allowed?("maxpro", 25)

      refute ExerciseCatalog.load_allowed?("maxpro", 0)
      refute ExerciseCatalog.load_allowed?("maxpro", 26)
      refute ExerciseCatalog.load_allowed?("maxpro", 12.5)
    end

    test "a bodyweight movement takes any number, including a negative one" do
      # The number is load added (a belt) or taken away (an assist), which is how a
      # pull-up gets easier without a second machine.
      assert ExerciseCatalog.load_allowed?("pull_up_bar", 0)
      assert ExerciseCatalog.load_allowed?("pull_up_bar", 20)
      assert ExerciseCatalog.load_allowed?("pull_up_bar", -20)

      refute ExerciseCatalog.load_allowed?("pull_up_bar", "heavy")
    end

    test "a piece this gym does not have has no ladder at all" do
      refute ExerciseCatalog.load_allowed?("barbell", 60)
      refute ExerciseCatalog.load_allowed?("dumbbells", "heavy")
    end

    test "a movement's equipment is the piece it stands at" do
      assert ExerciseCatalog.equipment_for("goblet_squat") == "dumbbells"
      assert ExerciseCatalog.equipment_for("kb_swing") == "kettlebell"
      assert ExerciseCatalog.equipment_for("dead_hang") == "pull_up_bar"
      assert ExerciseCatalog.equipment_for("dumbbell_bench_press") == nil
    end
  end

  defp read_schema(name) do
    path = Path.join(@schema_path, name)

    assert File.exists?(path),
           """
           The published schema is missing: #{path}

           A schema that is not there cannot be kept in step with the code.
           If the workspace is incomplete, run scripts/install_workspace.sh.
           """

    path |> File.read!() |> Jason.decode!()
  end
end

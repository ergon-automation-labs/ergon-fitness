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

    test "the dumbbells start at 10 and step by 5" do
      assert ExerciseCatalog.load_settings("dumbbells") == %{"min" => 10.0, "step" => 5.0}
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

    test "every piece makes at least three movements possible" do
      for equipment <- ExerciseCatalog.equipment() do
        movements = ExerciseCatalog.by_equipment(equipment["value"])

        assert length(movements) >= 3,
               "#{equipment["value"]} is in the gym but offers #{length(movements)} movements"
      end
    end

    test "every piece offers at most six, so one screen can hold it" do
      # A menu is where a foggy moment goes to become a nineteen-item list. Six is
      # the ceiling a picker can show at once without becoming a chore.
      for equipment <- ExerciseCatalog.equipment() do
        assert length(ExerciseCatalog.by_equipment(equipment["value"])) <= 6
      end
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
                 ~w(activity equipment label max measure min value)
      end
    end

    test "the options reply carries the gym beside the activities" do
      reply = WorkoutHandler.handle_options(%{}) |> Jason.decode!()

      assert reply["data"]["equipment"] == ExerciseCatalog.equipment()
      assert reply["data"]["exercises"] == ExerciseCatalog.exercise_options()
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

    test "the reply requires the gym it always sends" do
      schema = read_schema("fitness.workout.options.reply.json")

      assert schema["properties"]["data"]["required"] |> Enum.sort() ==
               ~w(equipment exercises intensities workout_types)
    end

    test "there is an example proving each load kind is exercisable" do
      path = Path.join(@schema_path, "../examples/fitness.workout.options.reply.json")
      body = path |> File.read!() |> Jason.decode!()
      loads = body["data"]["equipment"] |> Enum.map(& &1["load"]) |> Enum.uniq()

      assert Enum.sort(loads) == ["bodyweight", "kg", "level"]
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

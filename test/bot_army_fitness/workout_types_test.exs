defmodule BotArmyFitness.WorkoutTypesTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.WorkoutTypes

  # The schemas repo is a sibling in the workspace (`config/repos.toml` lists it,
  # `scripts/install_workspace.sh` provisions it), so this path is part of the
  # workspace contract rather than a private accident. A guard that quietly
  # skips when it cannot find the file it guards is not a guard.
  @schema_path Path.expand("../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)

  describe "the canonical lists" do
    test "types are unique, lower-case, and non-empty" do
      assert WorkoutTypes.types() |> Enum.uniq() == WorkoutTypes.types()
      refute Enum.any?(WorkoutTypes.types(), &(&1 == ""))
      assert Enum.all?(WorkoutTypes.types(), &(&1 == String.downcase(&1)))
    end

    test "intensities are the three the surfaces offer" do
      assert WorkoutTypes.intensities() == ["light", "moderate", "intense"]
    end

    test "every type has a label that is not the raw value" do
      for type <- WorkoutTypes.types() do
        label = WorkoutTypes.label(type)
        assert is_binary(label)
        assert label != ""
        assert String.upcase(String.first(label)) == String.first(label)
      end
    end

    test "hiit keeps its acronym capitalisation" do
      assert WorkoutTypes.label("hiit") == "HIIT"
    end
  end

  describe "normalise_type/1" do
    test "passes a canonical value through" do
      for type <- WorkoutTypes.types() do
        assert WorkoutTypes.normalise_type(type) == type
      end
    end

    test "folds the aliases each surface used to use" do
      assert WorkoutTypes.normalise_type("run") == "running"
      assert WorkoutTypes.normalise_type("bike") == "cycling"
      assert WorkoutTypes.normalise_type("swim") == "swimming"
      assert WorkoutTypes.normalise_type("stretch") == "stretching"
      assert WorkoutTypes.normalise_type("cardio") == "running"
      assert WorkoutTypes.normalise_type("flexibility") == "stretching"
      assert WorkoutTypes.normalise_type("weight_training") == "strength"
      assert WorkoutTypes.normalise_type("Strength Training") == "strength"
    end

    test "is case- and separator-insensitive" do
      assert WorkoutTypes.normalise_type("  YOGA  ") == "yoga"
      assert WorkoutTypes.normalise_type("Weight_Training") == "strength"
      assert WorkoutTypes.normalise_type("weight-training") == "strength"
    end

    test "folds free text onto `other` rather than refusing the log" do
      # discord.check_in.response sends a bare exercise name, e.g. "pushups".
      assert WorkoutTypes.normalise_type("pushups") == "other"
      assert WorkoutTypes.normalise_type("workout") == "other"
      assert WorkoutTypes.normalise_type("") == "other"
      assert WorkoutTypes.normalise_type(nil) == "other"
      assert WorkoutTypes.normalise_type(42) == "other"
    end

    test "always returns a stored value" do
      for value <- ["run", "PUSH-UPS", "", nil, 7, "yoga"] do
        assert WorkoutTypes.known?(WorkoutTypes.normalise_type(value))
      end
    end
  end

  describe "values/0 — what may be stored" do
    test "is the offered types plus the catch-all" do
      assert WorkoutTypes.values() == WorkoutTypes.types() ++ ["other"]
    end

    test "the catch-all is not something a picker should offer" do
      refute "other" in WorkoutTypes.types()
      assert WorkoutTypes.other() == "other"
    end

    test "known?/1 accepts a canonical type and the catch-all, and nothing else" do
      assert Enum.all?(WorkoutTypes.types(), &WorkoutTypes.known?/1)
      assert WorkoutTypes.known?("other")
      refute WorkoutTypes.known?("pushups")
      refute WorkoutTypes.known?(nil)
    end
  end

  describe "normalise_intensity/1" do
    test "passes a canonical value through" do
      for intensity <- WorkoutTypes.intensities() do
        assert WorkoutTypes.normalise_intensity(intensity) == intensity
      end
    end

    test "folds the aliases the schema and surfaces used" do
      assert WorkoutTypes.normalise_intensity("vigorous") == "intense"
      assert WorkoutTypes.normalise_intensity("high") == "intense"
      assert WorkoutTypes.normalise_intensity("hard") == "intense"
      assert WorkoutTypes.normalise_intensity("medium") == "moderate"
      assert WorkoutTypes.normalise_intensity("easy") == "light"
      assert WorkoutTypes.normalise_intensity("LOW") == "light"
    end

    test "falls back to moderate, the column's own default" do
      assert WorkoutTypes.normalise_intensity(nil) == "moderate"
      assert WorkoutTypes.normalise_intensity("") == "moderate"
      assert WorkoutTypes.normalise_intensity("sideways") == "moderate"
    end
  end

  describe "parity with the published schema" do
    # `bot_army_schemas_fitness` is a separate repo, so nothing else would catch
    # the enums drifting away from the code again. These are the only guard.
    #
    # The request schema deliberately carries no enum on `workout_type` or
    # `intensity`: free text is what the bot accepts, because
    # `discord.check_in.response` sends a bare exercise name and a strict enum
    # would call a request the bot must handle invalid. The guarantee lives on
    # the other side — what got stored — so the enums are asserted on the reply.
    test "the request accepts free text for workout_type and intensity" do
      schema = read_schema("fitness.workout.log.json")
      properties = schema["properties"]["payload"]["properties"]

      for field <- ~w(workout_type intensity) do
        refute Map.has_key?(properties[field], "enum"),
               "#{field} is folded from free text, so an enum here would describe " <>
                 "a request the bot has to accept as invalid"

        assert properties[field]["type"] == "string"
        assert properties[field]["minLength"] == 1
      end
    end

    test "the reply's workout_type enum matches WorkoutTypes.values/0" do
      schema = read_schema("fitness.workout.log.reply.json")
      data = schema["oneOf"] |> Enum.find(& &1["properties"]["data"])

      assert data["properties"]["data"]["properties"]["workout_type"]["enum"] ==
               WorkoutTypes.values()
    end

    test "the reply's intensity enum matches WorkoutTypes.intensities/0" do
      schema = read_schema("fitness.workout.log.reply.json")
      data = schema["oneOf"] |> Enum.find(& &1["properties"]["data"])

      assert data["properties"]["data"]["properties"]["intensity"]["enum"] ==
               WorkoutTypes.intensities()
    end

    test "the schema requires exactly the fields the handler requires" do
      schema = read_schema("fitness.workout.log.json")

      assert schema["properties"]["payload"]["required"] |> Enum.sort() ==
               ~w(duration_minutes workout_type)
    end

    test "there is an example proving free text is accepted" do
      example = Path.join(@schema_path, "../examples/fitness.workout.log.free_text.json")

      assert File.exists?(example),
             "free text is the request contract, so an example must exercise it: #{example}"

      body = example |> File.read!() |> Jason.decode!()
      assert WorkoutTypes.normalise_type(body["workout_type"]) == "other"
      assert WorkoutTypes.normalise_intensity(body["intensity"]) in WorkoutTypes.intensities()
    end

    test "no schema is left over for a subject that does not exist" do
      stale = Path.join(@schema_path, "fitness.workout.json")

      refute File.exists?(stale),
             """
             #{stale} names no subject. It required `workout_id`/`title`/`date`
             and enums no handler has ever used, so it could only mislead.
             """
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

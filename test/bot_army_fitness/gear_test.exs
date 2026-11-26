defmodule BotArmyFitness.GearTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.{ExerciseCatalog, Gear}

  # A set row in the shape the store answers with, for the piece named.
  defp set(exercise, date, amount, load_kind, load_value) do
    %{
      "exercise" => exercise,
      "measure" => "reps",
      "amount" => amount,
      "load_kind" => load_kind,
      "load_value" => load_value,
      "date" => date
    }
  end

  describe "the room" do
    test "starts where the catalog says the cable machine usually is" do
      # The catalog's note is the only place this house's default is written down:
      # "set up on the floor most of the time". The state has to agree with it, or the
      # prose and the plan would be two different claims about one room.
      state = Gear.state()

      assert state["maxpro"] == "floor"
      assert state["bell"] == nil
    end

    test "offers the two places the cable machine can stand" do
      assert Gear.positions() == ["floor", "wall"]
    end

    test "reads the bell's setting off her log, because there is only one bell" do
      history = %{
        "kb_clean_press" => [
          set("kb_clean_press", "2026-11-24", 8, "kg", 24.5),
          set("kb_clean_press", "2026-11-20", 8, "kg", 18.0)
        ]
      }

      assert Gear.state(history)["bell"] == 24.5
    end

    test "the newest bell set across every bell movement is the one on the floor" do
      history = %{
        "kb_clean_press" => [set("kb_clean_press", "2026-11-20", 8, "kg", 18.0)],
        "kb_row" => [set("kb_row", "2026-11-24", 10, "kg", 31.0)]
      }

      assert Gear.state(history)["bell"] == 31.0
    end

    test "a log with no kettlebell in it has an unknown bell rather than a guessed one" do
      # A dumbbell set says nothing about the bell, and an invented setting would be this
      # module making a claim about a room it did not read.
      history = %{"floor_press" => [set("floor_press", "2026-11-24", 10, "kg", 20.0)]}

      assert Gear.state(history)["bell"] == nil
    end

    test "a history in some other shape is read as an unknown bell, not a crash" do
      assert Gear.state(%{"kb_row" => :not_a_list})["bell"] == nil
      assert Gear.state(:not_a_history) == %{"maxpro" => "floor", "bell" => nil}
    end
  end

  describe "what a movement asks of the room" do
    test "a movement done lying down works with the cable machine on the floor" do
      for movement <- ~w(cable_chest_press cable_fly cable_crunch) do
        assert Gear.needs(movement) == nil
        assert Gear.ready?(movement, Gear.state())
      end
    end

    test "a movement whose cable must leave the machine above the floor needs the wall" do
      for movement <- ~w(lat_pulldown cable_shoulder_press cable_row triceps_pushdown) do
        assert Gear.needs(movement) == "wall"
        refute Gear.ready?(movement, Gear.state())
        assert Gear.ready?(movement, %{"maxpro" => "wall"})
      end
    end

    test "every movement of the cable machine has a verdict, and only it has one" do
      # The rule is about the cable machine's setup. A dumbbell, a bell, the bars and the
      # bar are ready however the cable is standing — a plan that made a kettlebell wait on
      # a wall would be a plan inventing a dependency.
      for movement <- ExerciseCatalog.by_equipment("maxpro") do
        assert Gear.needs(movement["value"]) in [nil, "wall"]

        refute Gear.ready?(movement["value"], Gear.state()) and
                 Gear.needs(movement["value"]) == "wall"
      end

      for equipment <- ExerciseCatalog.equipment(),
          equipment["value"] != "maxpro",
          movement <- ExerciseCatalog.by_equipment(equipment["value"]) do
        assert Gear.needs(movement["value"]) == nil
        assert Gear.ready?(movement["value"], Gear.state())
      end
    end

    test "the floor's ready set is exactly the movements that are done lying down" do
      floor_ready =
        ExerciseCatalog.by_equipment("maxpro")
        |> Enum.map(& &1["value"])
        |> Enum.filter(&Gear.ready?(&1, Gear.state()))
        |> Enum.sort()

      assert floor_ready == ~w(cable_chest_press cable_crunch cable_fly)
    end

    test "a name outside the gym asks nothing of the room" do
      assert Gear.needs("bench_press_with_a_barbell_we_do_not_have") == nil
      assert Gear.needs(nil) == nil
    end

    test "a state it cannot read makes nothing ready rather than everything" do
      refute Gear.ready?("cable_chest_press", :not_a_state)
      refute Gear.ready?("cable_chest_press", nil)
    end

    test "a requirement is said in words a person can act on" do
      assert Gear.words("wall") == "the wall attachment"
      assert Gear.words(nil) == nil
    end
  end
end

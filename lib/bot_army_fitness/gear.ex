defmodule BotArmyFitness.Gear do
  @moduledoc """
  How the gym stands right now, and what a movement asks of the piece it is done on.

  `ExerciseCatalog` says what this house *has*. This module says how it is *made
  available* — the fact the catalog carries as prose and a plan needs as a value.

  ## The cable machine has two rooms in it

  The MaxPRO can stand **on the floor**, cables leaving at ground level, which is how it
  is used most of the time; or **at the wall**, on the attachment that gives it a pulley
  above the floor. The catalog's own note says so. The two are not the same menu with a
  different label: a movement whose cable must leave the machine above the floor cannot
  be done on a floor day, and a floor day that led a slot with one would be a plan for a
  room she is not standing in.

  The line between them is the height the cable leaves the machine at, so it is short:

    * a **lying** movement works from a floor-level cable — the press, the fly, the
      crunch, all done on her back with the unit on the floor
    * everything else on the MaxPRO wants a pulley above the floor: a pulldown, a row, a
      face pull, a press from a standing or seated position, a pushdown

  Nothing here declares a movement impossible. `ready?/2` is an *ordering* fact: the
  plans built from it lead with what works in the room as it stands, and a movement that
  needs the wall stays on the wire with `"needs"` beside it, so the cost of changing the
  room — a plate on a wall, a minute — is said out loud rather than hidden.

  ## The bell is at one of seven settings, and her log already says which

  The kettlebell is a single bell. Whatever its newest logged set was loaded at is where
  it is now — there is no other place it could be — so `state/1` reads that off her log
  instead of asking her a question she has already answered by lifting it. The
  dumbbells need no such reading: every load from 10 to 55 kg is in the rack.

  ## The wall is a fact about the room, and it is one stored row

  `state/1` answers the house's default — the floor — because that is what the catalog
  says the room usually looks like, and because a caller with no database (a test, a pure
  rule) still deserves an answer. The real state comes from
  `BotArmyFitness.GearSetupStore` through `state/2`, and a press on the card flips it
  (`fitness.gear.setup`). Nothing else in this module changes when it is raised or put
  back: every caller already takes the state as an argument it does not invent.
  """

  alias BotArmyFitness.ExerciseCatalog

  @floor "floor"
  @wall "wall"

  # The MaxPRO movements that work with the unit on the floor: each is done lying down,
  # so the cable leaves the machine at floor level, which is exactly where a floor day
  # has it. Every other movement of the piece wants a pulley above the floor.
  @from_the_floor ~w(cable_chest_press cable_fly cable_crunch)

  @positions [@floor, @wall]

  @doc "The places the cable machine can stand, in the order a card should offer them."
  @spec positions() :: [String.t()]
  def positions, do: @positions

  @doc """
  The state of the room, as a plan reads it.

  Keys:

    * `"maxpro"` — `"floor"` or `"wall"`, which is where the cable machine is set up
    * `"bell"` — the kettlebell's current setting in kg, read from the newest kettlebell
      set in `history` (newest first per movement, the shape
      `BotArmyFitness.WorkoutSetStore` answers with), or `nil` when she has never logged
      one

  `history` is optional so a caller with no log can still ask what the room looks like:
  the floor and a bell of unknown setting, which is the truth on a day the log is not
  available.
  """
  @spec state() :: map()
  @spec state(map() | term()) :: map()
  @spec state(map() | term(), term()) :: map()
  def state(history \\ %{})

  def state(history) when is_map(history), do: state(history, @floor)

  def state(_history), do: state(%{}, @floor)

  @doc """
  The room as it stands, given the cable machine's stored `position`.

  A position this module does not know is read as the floor — the state the catalog says
  the room is *usually* in — because `GearSetupStore` already refuses unknown words and a
  caller that cannot say where the machine is has a failed read it should have refused
  one step earlier. The history is still optional, for the same reason it is in `state/1`.
  """
  def state(history, position) when is_map(history) and position in @positions do
    %{"maxpro" => position, "bell" => bell_setting(history)}
  end

  def state(history, _position) when is_map(history), do: state(history, @floor)

  def state(_history, _position), do: %{"maxpro" => @floor, "bell" => nil}

  @doc """
  What a movement asks of the room: `nil` when it works as the room usually stands, or
  the piece of the setup it needs — `"wall"` for the cable machine's attachment.

  A movement on a piece this house does not have answers `nil`: this module is about the
  setup of the pieces it knows, and refusing an unknown name is the catalog's job.
  """
  @spec needs(term()) :: String.t() | nil
  def needs(movement) do
    cond do
      ExerciseCatalog.equipment_for(movement) != "maxpro" -> nil
      movement in @from_the_floor -> nil
      true -> @wall
    end
  end

  @doc """
  Whether `movement` can be done with the room in `state`.

  A movement with no requirement is always ready. A movement that needs the wall is ready
  only when the cable machine is at the wall. Anything that is not a state map answers
  `false`: a caller that cannot say how the room stands has a failed read, and a failed
  read must not be read as "everything is fine".
  """
  @spec ready?(term(), term()) :: boolean()
  def ready?(movement, state) when is_map(state) do
    case needs(movement) do
      nil -> true
      needed -> needed == Map.get(state, "maxpro", @floor)
    end
  end

  def ready?(_movement, _state), do: false

  @doc """
  The words a card uses for a requirement, or `nil` when there is nothing to say.

  A movement that works in the room as it stands says nothing: its row is already the
  sentence. A movement that needs the wall says which piece of it, because "the wall
  attachment" is a thing she can go and hang, and "unavailable" is not.
  """
  @spec words(term()) :: String.t() | nil
  def words(@wall), do: "the wall attachment"
  def words(_needs), do: nil

  # The newest kettlebell set across every kettlebell movement, by the day it was logged.
  # Ties keep the history's own order, so the same log always answers the same setting.
  defp bell_setting(history) do
    history
    |> Enum.filter(fn {movement, sets} ->
      ExerciseCatalog.equipment_for(movement) == "kettlebell" and is_list(sets) and sets != []
    end)
    |> Enum.map(fn {_movement, [newest | _rest]} -> newest end)
    |> Enum.filter(&is_map/1)
    |> Enum.sort_by(& &1["date"], :desc)
    |> case do
      [%{"load_value" => load} | _rest] when is_number(load) -> load
      _none -> nil
    end
  end
end

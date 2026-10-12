defmodule BotArmyFitness.WorkoutTypes do
  @moduledoc """
  The one vocabulary for workout types and intensities.

  Four lists were in play and none agreed with any other:

    * the JSON schema (`bot_army_schemas_fitness`) said
      `cardio | strength | flexibility | sports | mixed`;
    * the rotation plan (`TodayPlanHandler`) held display names
      (`"Strength Training"`, `"Yoga"`) and downcased them onto the wire, so
      `"strength training"` could never equal a picker's `"strength"`;
    * the phone offered `run | walk | strength | yoga | swim | bike | sports |
      stretch`;
    * the dashboard handheld forwarded whatever `exercise_type` the plan carried.

  Nothing lined up, so no report could group two rows of the same activity and a
  picker's value could never match a stored one.

  This module is the single list. `normalise_type/1` folds the aliases and the
  free text that arrive from elsewhere onto it — Discord check-ins send a bare
  exercise name (`"pushups"`) — mapping what it does not recognise to `"other"`
  rather than refusing the log, so the human's own word still survives in the
  workout's `title` while the reportable field stays comparable.

  So there are two lists and they mean different things. `types/0` is what a
  picker should offer and what a *request* may be folded onto. `values/0` adds
  `"other"` and is what the bot may *store* — a request is free text, a stored
  row is always one of these. The reply schema
  (`bot_army_schemas_fitness/schemas/fitness.workout.log.reply.json`) carries
  `values/0` as its enum, and the request schema carries no enum at all because
  free text is its contract; a test here asserts the reply's enum stays equal.
  """

  @types ~w(running walking cycling swimming strength yoga hiit sports stretching)
  @intensities ~w(light moderate intense)
  @other "other"

  @type_aliases %{
    "run" => "running",
    "running" => "running",
    "jog" => "running",
    "jogging" => "running",
    "walk" => "walking",
    "walking" => "walking",
    "bike" => "cycling",
    "biking" => "cycling",
    "cycle" => "cycling",
    "cycling" => "cycling",
    "swim" => "swimming",
    "swimming" => "swimming",
    "strength" => "strength",
    "strength training" => "strength",
    "weights" => "strength",
    "weight training" => "strength",
    "lifting" => "strength",
    "yoga" => "yoga",
    "hiit" => "hiit",
    "interval" => "hiit",
    "intervals" => "hiit",
    "sports" => "sports",
    "sport" => "sports",
    "stretch" => "stretching",
    "stretching" => "stretching",
    "flexibility" => "stretching",
    "cardio" => "running"
  }

  @intensity_aliases %{
    "light" => "light",
    "easy" => "light",
    "low" => "light",
    "moderate" => "moderate",
    "medium" => "moderate",
    "normal" => "moderate",
    "intense" => "intense",
    "vigorous" => "intense",
    "high" => "intense",
    "hard" => "intense"
  }

  @doc "The canonical workout types, in the order surfaces should offer them."
  def types, do: @types

  @doc """
  Every type the bot may **store**: `types/0` plus the catch-all.

  A request is free text, so an unrecognised word is kept rather than refused;
  what lands in the column is therefore always one of these. This is the list a
  schema enum should carry, and `types/0` is the list a picker should show —
  `"other"` is a real stored value and not an activity anyone chooses.
  """
  def values, do: @types ++ [@other]

  @doc "The standing-in type for a word this module does not recognise."
  def other, do: @other

  @doc "The canonical intensity levels."
  def intensities, do: @intensities

  @doc """
  Fold a workout type onto the canonical list.

  Case- and separator-insensitive (`"Weight_Training"` and `"weight training"`
  both become `"strength"`). An unrecognised word becomes `"other"` — the write
  is kept rather than refused, so a human's own exercise name is never lost.
  """
  def normalise_type(value) when is_binary(value) do
    key = value |> String.trim() |> String.downcase() |> String.replace(~r/[\s_-]+/, " ")

    cond do
      key == "" -> @other
      Map.has_key?(@type_aliases, key) -> Map.fetch!(@type_aliases, key)
      key in @types -> key
      true -> @other
    end
  end

  def normalise_type(_), do: @other

  @doc """
  Fold an intensity onto the canonical list.

  An unrecognised level becomes `"moderate"`, the same default the `workouts`
  column declares.
  """
  def normalise_intensity(value) when is_binary(value) do
    key = value |> String.trim() |> String.downcase()

    cond do
      key == "" -> "moderate"
      Map.has_key?(@intensity_aliases, key) -> Map.fetch!(@intensity_aliases, key)
      key in @intensities -> key
      true -> "moderate"
    end
  end

  def normalise_intensity(_), do: "moderate"

  @doc "A human label for a canonical workout type."
  def label("hiit"), do: "HIIT"
  def label(type) when type in @types, do: String.capitalize(type)
  def label(_), do: "Workout"

  @doc """
  Whether a value is a type this module knows.

  True for a canonical type and true for `"other"`, because `"other"` is a
  value the bot itself stores — `known?/1` answers "would this round-trip", not
  "is this an activity".
  """
  def known?(value), do: value in @types or value == @other
end

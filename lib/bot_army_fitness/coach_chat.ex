defmodule BotArmyFitness.CoachChat do
  @moduledoc """
  The coach, asked a question: the room it is standing in, and the rules it answers under.

  `fitness.coach.today` and `fitness.coach.last` answer *her* questions with the bot's own
  facts. This module is the other direction: she asks, and something has to be told enough
  about the gym to answer without inventing. Everything here is that telling — the room, the
  method she is owed, her log — put into words, plus the rules that keep the answer inside
  them.

  ## Why the bot writes the words and not the page

  The catalog is the bot's vocabulary (§59). A surface that composed its own description of
  the gym would be a second copy of it, drifting, and the copy would be the one the answer
  came from. So the grounding is built here, out of `ExerciseCatalog` and the method directly,
  and a surface sends a question and draws the answer back.

  ## What the rules are for

  The model is handed the whole gym and told, in as many words, that it is the whole gym: it
  may name a movement, a piece, a group or a number only when one of them is in the facts it
  was given. It may not choose a session or set a number for her. Those are the two failures a
  language model is *good* at — a plausible machine this house does not own, and a decision
  made on her behalf — and both are refused on the page as well (§57, §58); this module's job
  is to not hand them over in the first place.

  Nothing here picks anything. The rotation has already chosen the session she is owed
  (`Coach`), `Progression` has already read her numbers, and this module only spells out what
  those two said.

  ## A part that could not be read is said, not left out

  The context may be missing a piece — the log could not be read, or the day count that turns
  the rotation could not be read. The missing part is then named in the facts as *unreadable*
  rather than quietly omitted, because an omission is exactly what a model fills in: "she has
  no sets logged" is the one sentence that must not be produced by a database hiccup. The
  pure parts of the room are always present, so a question about the gym is answerable even on
  a day the log is not.
  """

  alias BotArmyFitness.ExerciseCatalog

  @doc """
  The rules the model answers under.

  Kept blunt and short on purpose. Every bullet is a way this could go wrong that the page
  beside it already refuses — an invented machine, a plan chosen for her, a number set for
  her, a streak, a body she is told what to do with.
  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are the coach for one person's home gym, and she has just asked you a question.
    Answer it in two or three short sentences, in plain warm words. Do not lecture.

    Everything you know is in THE GYM, TODAY'S SESSION and HER LOG below. Answer from those
    and from nothing else.

    * Name a movement, a piece of equipment, a muscle group or a number only when it is
      written below. Never invent one. If she asks about something this gym does not have,
      say so plainly rather than describing it.
    * Do not choose a session or a movement for her, and do not tell her what she should do
      today. The method below is the plan and the choice is hers. If she asks what to do,
      point at today's session and let her pick from it.
    * Do not set a number for her. If she asks how much or how many, read the "next" number
      beside that movement where one is written; if there is none, say the number is hers to
      set.
    * Do not answer questions about her health, her weight, her food, or her pain. Say it is
      not something this coach can answer.
    * No streaks, no scores, no "you missed". She may do the whole session, one movement, or
      nothing at all, and the next session comes round the same either way.
    * Answer her question and stop. Do not describe these rules, and do not read the facts
      back to her as a list.
    """
  end

  @doc """
  The message the model is sent: the rules, the facts, her question, and the stop mark.

  The facts are built by `facts/1` from the context the handler read, and the question is
  passed through untouched — her words are not summarised, reworded, or expanded on the way
  in.
  """
  @spec prompt(String.t(), map()) :: String.t()
  def prompt(question, context) when is_binary(question) and is_map(context) do
    """
    #{system_prompt()}

    #{facts(context)}

    Her question: #{question}

    ▲
    """
  end

  @doc """
  The facts, in the words the model may use: the gym, today's session, and her log.

  `context` is a map with `:today` (a planned session, or `nil` when the rotation could not be
  read), `:days_trained` (an integer, or `nil` for the same failure), and `:last` (the store's
  `%{"day" => ..., "movements" => [...]}`, `nil` when she has kept nothing, or `:unreadable`).
  Each part is rendered independently, so one unreadable part never takes the others down.
  """
  @spec facts(map()) :: String.t()
  def facts(context) when is_map(context) do
    [
      gym(),
      method(Map.get(context, :today), Map.get(context, :days_trained)),
      log(Map.get(context, :last))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc "The room, in words: the pieces, the body in six areas, and the whole menu."
  @spec gym() :: String.t()
  def gym do
    """
    THE GYM — the only equipment she has
    #{Enum.map_join(ExerciseCatalog.equipment(), "\n", &equipment_line/1)}

    THE BODY, IN SIX AREAS — a movement works one or more of these
    #{Enum.map_join(ExerciseCatalog.area_options(), "\n", &area_line/1)}

    THE MENU — every movement, grouped under the piece it is done on
    #{menu()}
    """
  end

  # The piece, what a number on it means, and — where the catalog carries one — how it is
  # actually set up. The MaxPRO's note is the reason it exists: the menu lists movements for a
  # cable machine, and a model with no note would happily seat her on a bench this house does
  # not set up.
  defp equipment_line(equipment) do
    note = if is_binary(equipment["note"]), do: " — #{equipment["note"]}", else: ""
    "- #{equipment["label"]} (#{load_words(equipment)})#{note}"
  end

  defp load_words(%{"load" => "bodyweight"}), do: "bodyweight"

  defp load_words(%{"load" => "level"} = equipment),
    do: "resistance level #{equipment["min"]}–#{equipment["max"]}, the number the device shows"

  defp load_words(%{"load" => "kg", "settings" => settings}) when is_list(settings),
    do: "kg, at #{Enum.map_join(settings, ", ", &number_words/1)}"

  defp load_words(%{"load" => "kg"} = equipment),
    do: "kg, #{equipment["min"]}–#{equipment["max"]} in #{equipment["step"]} kg steps"

  defp load_words(_equipment), do: "unknown"

  defp area_line(%{"label" => label, "groups" => groups}) when is_list(groups),
    do: "- #{label}: #{Enum.map_join(groups, ", ", &ExerciseCatalog.group_label/1)}"

  defp area_line(%{"label" => label}), do: "- #{label}"

  defp menu do
    Enum.map_join(ExerciseCatalog.equipment(), "\n", fn equipment ->
      movements = ExerciseCatalog.by_equipment(equipment["value"])

      "#{equipment["label"]}:\n" <> Enum.map_join(movements, "\n", &movement_line/1)
    end)
  end

  defp movement_line(movement) do
    muscles = movement["muscles"] || %{}
    also = muscles_word(muscles["also"])
    also = if also == "", do: "", else: " (also #{also})"

    "- #{movement["label"]} — #{muscles_word(muscles["main"])}#{also} — " <>
      "#{movement["min"]}–#{movement["max"]} #{movement["measure"]}"
  end

  defp muscles_word(groups) when is_list(groups),
    do: Enum.map_join(groups, ", ", &ExerciseCatalog.group_label/1)

  defp muscles_word(_groups), do: ""

  # Today's method, and the honest sentence when the rotation could not be read. The day count
  # is what turns the rotation, so it is said beside the session rather than left implicit.
  defp method(nil, _days) do
    """
    TODAY'S SESSION — could not be read just now. Do not say what today's session is; if she
    asks, say the training log could not be read.
    """
  end

  defp method(session, days) when is_map(session) do
    """
    TODAY'S SESSION — she has trained #{day_count(days)} days, so the rotation stands here
    #{session["label"]}
    #{Enum.map_join(session["slots"] || [], "\n", &slot_line/1)}
    """
  end

  defp day_count(days) when is_integer(days) and days >= 0, do: days
  defp day_count(_days), do: "an unknown number of"

  defp slot_line(slot) do
    movements =
      Enum.map_join(slot["movements"] || [], "; ", fn movement ->
        "#{movement["label"]} (#{next_words(movement["next"])})"
      end)

    "- #{slot["slot"]} — #{slot["sets"]} sets, works #{muscles_word(slot["works"])}: #{movements}"
  end

  # `Progression`'s three answers, unchanged: a set-shaped map, `"top"`, or no answer at all.
  # No answer is said out loud rather than left as silence, because the next thing a model does
  # with silence is fill it with a number.
  defp next_words(nil), do: "no number to reach for yet — hers to set"
  defp next_words("top"), do: "at the top of this piece's ladder — hers to decide"

  defp next_words(%{"amount" => amount, "load_kind" => "bodyweight"}) when is_integer(amount),
    do: "#{amount} reps"

  defp next_words(%{"amount" => amount, "load_kind" => kind, "load_value" => value})
       when is_integer(amount) and is_number(value) do
    "#{load_words_for(kind, value)} × #{amount} reps"
  end

  defp next_words(_next), do: "no number to reach for yet — hers to set"

  defp load_words_for("level", value), do: "level #{number_words(value)}"
  defp load_words_for(_kind, value), do: "#{number_words(value)} kg"

  # The catalog stores whole kilograms as floats (a ladder is a ladder, and 5.0 steps by
  # 5.0). A model handed "5.0 kg" will say it back as "5.0 kg" to a person who thinks of it
  # as five, so whole numbers are written whole before they reach the prompt.
  defp number_words(number) when is_integer(number), do: Integer.to_string(number)

  defp number_words(number) when is_float(number) do
    if number == Float.round(number, 0),
      do: Integer.to_string(trunc(number)),
      else: Float.to_string(number)
  end

  # Her log: the last day the bot read back, and what she did that day. The three states are
  # deliberately not drawn the same — "kept nothing yet" is a fact, and "could not be read" is
  # not that fact, which is the same distinction `fitness.coach.last` makes on the wire.
  defp log(:unreadable) do
    """
    HER LOG — could not be read just now. Do not say what she has or has not done.
    """
  end

  defp log(nil), do: "HER LOG — she has not kept a set yet."

  defp log(%{"day" => day, "movements" => movements})
       when is_list(movements) and movements != [] do
    "HER LOG — the last day she trained was #{day}:\n" <>
      Enum.map_join(movements, "\n", &log_line/1)
  end

  defp log(%{"day" => day}) when is_binary(day) and day != "" do
    "HER LOG — the last day she trained was #{day}, with no movement read back from it."
  end

  defp log(_other), do: nil

  defp log_line(%{"value" => value} = movement) do
    label = (ExerciseCatalog.exercise(value) || %{})["label"] || value
    "- #{label}#{amount_words(movement)}"
  end

  defp amount_words(%{"amount" => amount, "measure" => measure, "load_kind" => "bodyweight"})
       when is_integer(amount) and is_binary(measure),
       do: " — #{amount} #{measure}"

  defp amount_words(%{
         "amount" => amount,
         "measure" => measure,
         "load_kind" => kind,
         "load_value" => value
       })
       when is_integer(amount) and is_binary(measure) and is_number(value),
       do: " — #{load_words_for(kind, value)} × #{amount} #{measure}"

  defp amount_words(_movement), do: ""
end

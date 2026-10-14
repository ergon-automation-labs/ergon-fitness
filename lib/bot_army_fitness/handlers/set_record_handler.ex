defmodule BotArmyFitness.Handlers.SetRecordHandler do
  @moduledoc """
  Records one set of one movement: `fitness.set.record`.

  A movement press is not a workout press. A workout row answers *how long* and
  *how hard*, and a home gym progresses in a different sentence: **how much, how
  many**. That sentence has its own table (`workout_sets`), its own verb, and this
  handler; the movement's own name and measure come from
  `BotArmyFitness.ExerciseCatalog`, which is the one place that knows the gym.

  ## What is refused, and why it is a refusal and not a round

  A number that is not on the equipment's own ladder is refused
  (`:load_not_on_ladder`) rather than snapped to the nearest setting. The ladder is
  the device's fact — the kettlebell has seven settings and 23 kg is not one of
  them — so accepting 23 would record a set that never happened, and later reads
  would build a progression on a weight that does not exist. The same rule the
  surface holds (`Fitness.range/1` never draws a measure it would not store) applies
  here to what the store keeps.

  The movement's `measure` and `load_kind` are **derived** from the catalog rather
  than taken from the request: a caller that sent `"measure": "reps"` for a dead hang
  would be describing the movement, and describing a movement is the catalog's job.

  A request for a movement this gym does not have is refused
  (`:unknown_movement`). Anything the catalog knows is stored, including a
  bodyweight movement with no number at all — an absent number there means the body
  alone, which is a fact and not a missing field.

  ## The answer carries what comes next as well as what came before

  A kept set answers with the row, the row before it, and the set to reach for next
  (`BotArmyFitness.Progression`). All three come from **one** read of the movement's
  newest rows, taken after the insert.

  That read is ordered by `date` and then `inserted_at`, so the row just kept is
  **not** necessarily at its head: a day logged in the past sorts below a set she
  already has, and the newest row is then her latest real set rather than the one in
  this reply. So each of the two lines names the row it means instead of trusting a
  position:

    * `previous` is the newest row that is **not** the row just kept, so the card's
      "last time" can never be the set she is looking at — which is exactly the
      confusion a backfilled day would create.
    * `next` follows the **newest** row, which is the one just kept unless she logged
      a day in the past, in which case it follows her latest real set and deliberately
      not from the backfilled row.

  Both are the same rule stated twice: the row a line is about is the row it names.
  """

  require Logger

  alias BotArmyFitness.{ExerciseCatalog, Progression, WorkoutSetStore}
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Handle a `fitness.set.record` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, the same shape
  `WorkoutHandler.handle_log/1` answers with, so the consumer's clause is one line.
  """
  def handle_record(message) do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyLibraryCore.Tenant.extract_context(message)
    payload = request_payload(message)

    case validate(payload) do
      {:ok, %{exercise: exercise, amount: amount, load_value: load_value}} ->
        store_payload = %{
          "tenant_id" => tenant_id,
          "user_id" => user_id,
          "exercise" => exercise["value"],
          "measure" => exercise["measure"],
          "amount" => amount,
          "load_kind" => ExerciseCatalog.load_kind(exercise["equipment"]),
          "load_value" => load_value,
          "date" => Map.get(payload, "date")
        }

        case record_set(store_payload) do
          {:ok, set} ->
            Logger.info(
              "Set recorded: exercise=#{exercise["value"]}, amount=#{amount}, load=#{inspect(load_value)}"
            )

            BotArmyLibraryRuntime.Outcomes.emit("fitness", "set", "set_recorded", 1,
              metadata: %{
                set_id: set["id"],
                exercise: exercise["value"],
                amount: amount,
                load_kind: store_payload["load_kind"],
                load_value: load_value,
                tenant_id: tenant_id
              }
            )

            history = history(tenant_id, exercise["value"])

            Reply.ok(%{
              "set" => set,
              "previous" => previous_set(history, set),
              "next" => Progression.next_load(history)
            })

          {:error, reason} ->
            Logger.warning("Failed to record set: #{inspect(reason)}")

            BotArmyLibraryRuntime.Outcomes.emit("fitness", "set", "set_record_failed", 0,
              metadata: %{
                exercise: exercise["value"],
                reason: inspect(reason),
                tenant_id: tenant_id
              }
            )

            Reply.error("failed to record the set", :persist_failed)
        end

      {:error, reason} ->
        Logger.warning("Refused set record: #{inspect(reason)}")
        Reply.error(refusal_sentence(reason), reason)
    end
  end

  @doc """
  Validate a request against the movement's own menu.

  Pure and public so the rules are testable without a store or a broker. Returns
  `{:ok, %{exercise: …}}` with the movement's own catalog entry, or
  `{:error, reason}` naming exactly what was wrong.
  """
  @spec validate(map) :: {:ok, map} | {:error, atom}
  def validate(payload) when is_map(payload) do
    with {:ok, exercise} <- movement(payload["exercise"]),
         {:ok, amount} <- amount(payload["amount"]),
         {:ok, load_value} <- load(exercise, Map.get(payload, "load")) do
      {:ok, %{exercise: exercise, amount: amount, load_value: load_value}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_payload), do: {:error, :invalid_payload}

  @doc "The sentence a refusal answers with — the caller's words, not an inspect of an atom."
  @spec refusal_sentence(atom) :: String.t()
  def refusal_sentence(:unknown_movement), do: "that is not a movement in this gym"
  def refusal_sentence(:missing_exercise), do: "no movement was named"
  def refusal_sentence(:amount_not_a_count), do: "the reps must be a whole number above zero"

  def refusal_sentence(:load_not_on_ladder),
    do: "that weight is not one of the settings this equipment has"

  def refusal_sentence(:load_not_a_number), do: "the weight must be a number"
  def refusal_sentence(reason), do: "the set could not be read: #{inspect(reason)}"

  # Private functions

  # The consumer's request-reply path merges the body at the top level and only sets
  # `"event"`; an envelope leaves the fields under `"payload"`. Accept both, the same
  # two-shape rule `WorkoutHandler` follows — reading one shape only silently dropped
  # every flat request.
  defp request_payload(message), do: message["payload"] || message

  defp movement(nil), do: {:error, :missing_exercise}

  defp movement(value) when is_binary(value) do
    case ExerciseCatalog.exercise(value) do
      nil -> {:error, :unknown_movement}
      exercise -> {:ok, exercise}
    end
  end

  defp movement(_value), do: {:error, :unknown_movement}

  defp amount(value) when is_integer(value) and value > 0, do: {:ok, value}

  # A JSON number arrives as an integer when it has no fraction, but "12.0" is a
  # legitimate way to write twelve and refusing it would refuse a caller's
  # spelling rather than a wrong count.
  defp amount(value) when is_float(value) do
    if value > 0 and abs(value - Float.round(value)) < 0.000001 do
      {:ok, trunc(value)}
    else
      {:error, :amount_not_a_count}
    end
  end

  defp amount(_value), do: {:error, :amount_not_a_count}

  # An absent number is a fact for the body (the body alone) and simply unrecorded
  # elsewhere; only a number that the device cannot show is refused.
  defp load(_exercise, nil), do: {:ok, nil}

  defp load(exercise, value) when is_number(value) do
    equipment = exercise["equipment"]

    if ExerciseCatalog.load_allowed?(equipment, value) do
      {:ok, value * 1.0}
    else
      {:error, :load_not_on_ladder}
    end
  end

  defp load(_exercise, _value), do: {:error, :load_not_a_number}

  # The store call is wrapped because a store that cannot answer must not take the
  # consumer process down with it: every fitness subscription rides on this one
  # process, so a raise here would stop answering `fitness.workout.list` too.
  defp record_set(payload) do
    set_store().create(payload)
  rescue
    e -> {:error, e}
  end

  # The newest row that is not the row just kept. The read is ordered by the day she did
  # the set, not by when it was written, so a day logged in the past leaves the row just
  # kept somewhere below the head — and a "last time" taken by position would then name
  # the set she is looking at (measured live 2026-10-14: backfilling 2019-01-01 while a
  # 2026-10-13 row existed made `previous` the row just written). `next` reads the same
  # list by its head, because a suggestion that followed a backfilled row would send her
  # backwards — two lines, two named rows, one read.
  defp previous_set(history, set) do
    Enum.find(history, fn row -> row["id"] != set["id"] end)
  end

  # The movement's newest rows, newest first — the one read both halves of the answer
  # come from. An unreadable store answers with no history rather than with a wrong one:
  # "this is the first set in your log" and "the read did not answer" are two different
  # sentences and the cards say both, so an empty list here cannot become a lie.
  defp history(tenant_id, exercise) do
    case set_store().for_exercise(tenant_id, exercise, 2) do
      {:ok, sets} when is_list(sets) -> sets
      other -> Logger.warning("Could not read the last sets: #{inspect(other)}") && []
    end
  rescue
    e -> Logger.warning("Could not read the last sets: #{inspect(e)}") && []
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end
end

defmodule BotArmyFitness.IntentEvaluator do
  @moduledoc false

  use GenServer

  require Logger

  alias BotArmyRuntime.Intent.AccumulatedContext
  alias BotArmyRuntime.Intent.ActionHandler
  alias BotArmyRuntime.Intent.DeferHandler
  alias BotArmyRuntime.Intent.Publisher
  alias BotArmyRuntime.Intent.ThresholdModel

  @bot_name "fitness"
  @evaluate_interval_ms 5 * 60 * 1000

  @default_thresholds %{
    idle_minutes: %{min: 60, weight: 0.7},
    streak_at_risk: %{min: 1, weight: 0.3},
    random_threshold: 0.4
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec record_observations(map()) :: :ok
  def record_observations(pulse_data) do
    GenServer.cast(__MODULE__, {:record_observations, pulse_data})
  end

  @spec evaluate_now() :: {:ok, [any()]} | {:error, term()}
  def evaluate_now do
    GenServer.call(__MODULE__, :evaluate_now, 10_000)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :evaluate, @evaluate_interval_ms)
    {:ok, %{last_evaluation: nil, pending_defers: %{}}}
  end

  @impl true
  def handle_cast({:record_observations, pulse_data}, state) do
    observations = extract_observations(pulse_data)
    Enum.each(observations, &AccumulatedContext.record(@bot_name, &1))
    {:noreply, state}
  end

  @impl true
  def handle_call(:evaluate_now, _from, state) do
    results = do_evaluate()
    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_info(:evaluate, state) do
    results = do_evaluate()
    new_pending = process_defer_results(results, state.pending_defers)
    process_act_results(results)
    Process.send_after(self(), :evaluate, @evaluate_interval_ms)
    {:noreply, %{state | last_evaluation: DateTime.utc_now(), pending_defers: new_pending}}
  end

  @impl true
  def handle_info({:conv_reply, conversation_id, body}, state) do
    case Map.get(state.pending_defers, conversation_id) do
      nil ->
        Logger.debug("[Fitness.Intent] Ignoring conv_reply for unknown conversation")
        {:noreply, state}

      {action, details, config} ->
        DeferHandler.process_reply(@bot_name, conversation_id, body, details, config)
        {:noreply, %{state | pending_defers: Map.delete(state.pending_defers, conversation_id)}}
    end
  end

  @impl true
  def handle_info({:conv_timeout, conversation_id}, state) do
    if Map.has_key?(state.pending_defers, conversation_id) do
      Logger.debug("[Fitness.Intent] Defer conversation timed out")
      {:noreply, %{state | pending_defers: Map.delete(state.pending_defers, conversation_id)}}
    else
      {:noreply, state}
    end
  end

  defp do_evaluate do
    thresholds = get_thresholds()
    context = AccumulatedContext.snapshot(@bot_name)

    evaluate_intent("suggest_workout", thresholds, context)
  end

  defp evaluate_intent(action, thresholds, context) do
    case ThresholdModel.evaluate(@bot_name, action, thresholds, context) do
      {:ok, :act, details} ->
        Logger.info("[Fitness.Intent] Acting on #{action} (score=#{details.score})")

        case Publisher.publish_intent(@bot_name, action, %{
               threshold_result: details,
               context_snapshot: %{entry_count: context.entry_count}
             }) do
          {:proceed, intent_id, endorsements} ->
            Logger.info("[Fitness.Intent] Proceeding with #{action} (intent_id=#{intent_id})")
            [{:acted, action, intent_id, details, endorsements}]

          {:vetoed, vetoing_bot, reason} ->
            Logger.info("[Fitness.Intent] #{action} vetoed by #{vetoing_bot}: #{reason}")
            [{:vetoed, action, vetoing_bot, reason}]

          {:error, reason} ->
            Logger.warning("[Fitness.Intent] Failed to publish #{action}: #{inspect(reason)}")
            []
        end

      {:ok, :defer, details} ->
        Logger.debug("[Fitness.Intent] Deferring #{action} (score=#{details.score})")
        [{:deferred, action, details, context}]

      {:ok, :abort, details} ->
        Logger.debug("[Fitness.Intent] Aborting #{action} (score=#{details.score})")
        []

      {:error, :disabled} ->
        []

      {:error, reason} ->
        Logger.warning("[Fitness.Intent] Error evaluating #{action}: #{inspect(reason)}")
        []
    end
  end

  defp process_defer_results(results, pending_defers) do
    Enum.reduce(results, pending_defers, fn
      {:deferred, action, details, context}, acc ->
        config = defer_config(action)

        if config do
          case DeferHandler.handle_defer(@bot_name, action, details, context, config) do
            {:ok, conversation_id} ->
              Map.put(acc, conversation_id, {action, details, config})

            _ ->
              acc
          end
        else
          acc
        end

      _result, acc ->
        acc
    end)
  end

  defp process_act_results(results) do
    Enum.each(results, fn
      {:acted, action, intent_id, details, endorsements} ->
        config = act_config(action)

        ActionHandler.execute_action(
          @bot_name,
          action,
          intent_id,
          details,
          endorsements,
          config
        )

      _result ->
        :ok
    end)
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Act Configuration
  # ───────────────────────────────────────────────────────────────────────────

  defp act_config("suggest_workout") do
    [
      handler_fn: &__MODULE__.handle_suggest_workout_action/5
    ]
  end

  defp act_config(_), do: nil

  @doc false
  def handle_suggest_workout_action(bot_name, action, _intent_id, details, _endorsements) do
    BotArmyRuntime.NATS.Publisher.publish("notification.route.request", %{
      "event_id" => UUID.uuid4(),
      "triggered_by" => bot_name,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "category" => "health",
      "urgency" => "normal",
      "title" => "Workout suggestion",
      "body" => workout_body(details)
    })
  end

  defp workout_body(details) do
    idle_min = Map.get(details, :idle_minutes, 0)
    hours = div(trunc(idle_min), 60)
    streak = Map.get(details, :streak_at_risk, 0)

    cond do
      streak > 0 ->
        "Your workout streak is at risk — even a short session counts today."

      hours > 0 ->
        "You've been idle for #{hours} hour#{if hours != 1, do: "s", else: ""} — a quick workout could help."

      true ->
        "Time for a workout? Your body will thank you."
    end
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Defer Configuration
  # ───────────────────────────────────────────────────────────────────────────

  defp defer_config("suggest_workout") do
    [
      prompt_builder: &__MODULE__.build_suggest_workout_defer_prompt/3,
      delivery_fn: &__MODULE__.deliver_defer_message/4,
      llm_intent: "ask",
      timeout_ms: 15_000
    ]
  end

  defp defer_config(_), do: nil

  @doc false
  def build_suggest_workout_defer_prompt(action, details, context) do
    idle_min = get_in(context, [:summary, :idle_minutes]) || 0

    %{
      "text" =>
        "The user has been idle for #{div(trunc(idle_min), 60)} hours but conditions " <>
          "don't warrant a full workout suggestion (score #{Float.round(details.score, 2)}, " <>
          "reason: #{details.reason}). Write a one-sentence gentle encouragement " <>
          "about movement or activity. If not useful, respond: skip"
    }
  end

  @doc false
  def deliver_defer_message(bot_name, action, llm_response, _details) do
    message =
      case llm_response do
        %{"response" => "skip"} -> nil
        %{"response" => text} when is_binary(text) -> String.trim(text)
        _ -> nil
      end

    if message do
      BotArmyRuntime.NATS.Publisher.publish("notification.route.request", %{
        "event_id" => UUID.uuid4(),
        "triggered_by" => bot_name,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "category" => "health",
        "urgency" => "ambient",
        "title" => "#{String.capitalize(action)} suggestion",
        "body" => message
      })

      :ok
    else
      :ok
    end
  end

  def extract_observations(pulse_data) do
    observations = []

    idle_min =
      get_in(pulse_data, ["observations", "idle_minutes"]) || 0

    observations =
      if idle_min > 0 do
        [
          %{
            type: :idle_minutes,
            value: idle_min,
            observed_at: DateTime.utc_now(),
            metadata: %{source: "pulse"}
          }
          | observations
        ]
      else
        observations
      end

    streak_risk =
      get_in(pulse_data, ["observations", "streak_at_risk"]) || 0

    observations =
      if streak_risk > 0 do
        [
          %{
            type: :streak_at_risk,
            value: streak_risk,
            observed_at: DateTime.utc_now(),
            metadata: %{source: "pulse"}
          }
          | observations
        ]
      else
        observations
      end

    observations
  end

  defp get_thresholds do
    Application.get_env(:bot_army_fitness, :intent_thresholds, @default_thresholds)
  end
end

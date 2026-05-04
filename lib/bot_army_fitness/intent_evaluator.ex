defmodule BotArmyFitness.IntentEvaluator do
  @moduledoc false

  use GenServer

  require Logger

  alias BotArmyRuntime.Intent.AccumulatedContext
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
    {:ok, %{last_evaluation: nil}}
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
    Process.send_after(self(), :evaluate, @evaluate_interval_ms)
    {:noreply, %{state | last_evaluation: DateTime.utc_now()}}
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
        []

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

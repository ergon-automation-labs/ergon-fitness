defmodule BotArmyFitness.Application do
  @moduledoc """
  BotArmyFitness application supervisor.

  Manages fitness bot services:
  - NATS message consumer
  - Workout tracker
  - Goal progress monitor
  """

  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_workout_store()
      |> maybe_add_goal_store()
      |> maybe_add_goal_scheduler()
      |> maybe_add_pulse_publisher()
      |> maybe_add_tavern_memory()
      |> maybe_add_intent_evaluator()
      |> maybe_add_veto_listener()
      |> maybe_add_consumer()
      |> maybe_add_outcome_tracker()

    opts = [strategy: :one_for_one, name: BotArmyFitness.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyFitness.Repo | children]
  end

  defp maybe_add_workout_store(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.WorkoutStore, []} | children]
  end

  defp maybe_add_goal_store(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.GoalStore, []} | children]
  end

  defp maybe_add_goal_scheduler(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.GoalScheduler, []} | children]
  end

  defp maybe_add_pulse_publisher(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.PulsePublisher, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.NATS.Consumer, []} | children]
  end

  defp maybe_add_intent_evaluator(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.IntentEvaluator, []} | children]
  end

  defp maybe_add_veto_listener(children) do
    if @env == :test do
      children
    else
      veto_rules = [
        [bot: "gtd", action: "nudge", custom: &BotArmyFitness.VetoRules.veto_stale_nudge/1],
        [bot: "gtd", action: "remind"],
        [
          bot: "chore",
          action: "remind_overdue",
          custom: &BotArmyFitness.VetoRules.veto_chore_remind_after_workout/1
        ]
      ]

      child = {BotArmyRuntime.Intent.VetoListener, rules: veto_rules, bot_name: "fitness"}
      [child | children]
    end
  end

  defp maybe_add_tavern_memory(children) do
    if @env == :test, do: children, else: [{BotArmyFitness.TavernMemory, []} | children]
  end

  defp maybe_add_outcome_tracker(children) do
    if @env == :test,
      do: children,
      else: [
        {BotArmyLearning.OutcomeTracker,
         [repo: BotArmyFitness.Repo, name: :fitness_outcome_tracker]}
        | children
      ]
  end
end

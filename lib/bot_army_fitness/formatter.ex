defmodule BotArmyFitness.Formatter do
  @moduledoc """
  Message formatting for Fitness Bot non-LLM notifications.

  Formats workout confirmations, streak updates, milestone notifications,
  and structured messages with Fitness Bot's coaching voice.

  Reference: `/docs/north_star_docs/BOT_ARMY_PERSONALITY_NORTH_STAR.md`
  """

  require Logger
  alias BotArmyRuntime.Personality.Formatter

  @doc """
  Format workout logged notification.

  Used when a workout is successfully recorded.
  """
  def format(:workout_logged, %{"exercise_type" => type, "duration_minutes" => duration}) do
    Formatter.with_symbol(
      :fitness_bot,
      "Logged: #{type} for #{duration} minutes. Done."
    )
  end

  @doc """
  Format streak milestone notification.

  Used when a streak reaches a milestone.
  """
  def format(:streak_milestone, %{"days" => days}) do
    Formatter.with_symbol(
      :fitness_bot,
      "#{days} days. That's not luck, that's discipline."
    )
  end

  @doc """
  Format goal progress notification.

  Used to report progress toward a fitness goal.
  """
  def format(:goal_progress, %{"goal" => goal, "progress" => progress}) do
    Formatter.with_symbol(
      :fitness_bot,
      "Goal: #{goal}. Progress: #{progress}. Keep moving."
    )
  end

  @doc """
  Format recovery day notification.

  Used to signal a scheduled rest day.
  """
  def format(:recovery_day, %{}) do
    Formatter.with_symbol(
      :fitness_bot,
      "Rest day. Your body's adapting. Back tomorrow stronger."
    )
  end

  @doc """
  Format workout plan ready notification.

  Used when a new workout plan is generated.
  """
  def format(:plan_ready, %{"weeks" => weeks}) do
    Formatter.with_symbol(
      :fitness_bot,
      "Plan ready for the next #{weeks} weeks. Let's build something."
    )
  end

  @doc """
  Format error notification.

  Used when something goes wrong.
  """
  def format(:error, %{"message" => message}) do
    Formatter.with_symbol(:fitness_bot, "Something went wrong: #{message}")
  end

  def format(_type, _data) do
    Logger.warning("Unknown Fitness formatter type")
    Formatter.with_symbol(:fitness_bot, "Something happened.")
  end
end

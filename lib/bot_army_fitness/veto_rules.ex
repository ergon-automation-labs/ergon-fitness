defmodule BotArmyFitness.VetoRules do
  @moduledoc false

  alias BotArmyRuntime.Intent.AccumulatedContext

  @doc """
  Veto GTD nudge intents when the user has no recent workout activity.
  A nudge about stale tasks shouldn't fire if the user hasn't been active
  enough for task completion to be realistic.
  """
  @spec veto_stale_nudge(map()) :: boolean()
  def veto_stale_nudge(envelope) do
    case AccumulatedContext.snapshot("fitness") do
      %{entry_count: count} when count > 0 ->
        has_recent_workout?(envelope)

      _ ->
        false
    end
  end

  defp has_recent_workout?(_envelope) do
    case AccumulatedContext.latest("fitness", :workout_logged) do
      nil -> true
      _entry -> false
    end
  end

  @doc """
  Veto chore remind_overdue when the user just worked out.
  Don't pile on chore reminders right after exercise — give them a breather.
  """
  @spec veto_chore_remind_after_workout(map()) :: boolean()
  def veto_chore_remind_after_workout(_envelope) do
    case AccumulatedContext.latest("fitness", :workout_logged) do
      nil -> false
      _entry -> true
    end
  end
end

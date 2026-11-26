defmodule BotArmyFitness.WorkoutSetStoreBehaviour do
  @moduledoc """
  Behaviour for WorkoutSetStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback recent(binary, integer) :: {:ok, [map]}
  @callback for_exercise(binary, binary, integer) :: {:ok, [map]}
  @callback newest_per_exercise(binary, [binary]) :: {:ok, %{binary => [map]}}
  @callback distinct_days(binary) :: {:ok, [Date.t()]}
  @callback since(binary, Date.t()) :: {:ok, [map]}
  @callback recent_day(binary) :: {:ok, map | nil}
  @callback delete(binary, binary) :: {:ok, map} | {:error, atom}
  @callback clear :: :ok
end

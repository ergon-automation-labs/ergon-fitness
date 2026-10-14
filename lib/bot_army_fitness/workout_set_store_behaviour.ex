defmodule BotArmyFitness.WorkoutSetStoreBehaviour do
  @moduledoc """
  Behaviour for WorkoutSetStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback recent(binary, integer) :: {:ok, [map]}
  @callback for_exercise(binary, binary, integer) :: {:ok, [map]}
  @callback newest_per_exercise(binary, [binary]) :: {:ok, %{binary => [map]}}
  @callback distinct_days(binary) :: {:ok, [Date.t()]}
  @callback clear :: :ok
end

defmodule BotArmyFitness.WorkoutSetStoreBehaviour do
  @moduledoc """
  Behaviour for WorkoutSetStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback recent(binary, integer) :: {:ok, [map]}
  @callback for_exercise(binary, binary, integer) :: {:ok, [map]}
  @callback previous_for_exercise(binary, binary) :: {:ok, map | nil}
  @callback clear :: :ok
end

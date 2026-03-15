defmodule BotArmyFitness.WorkoutStoreBehaviour do
  @moduledoc """
  Behaviour for WorkoutStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback get(binary) :: {:ok, map} | {:error, term}
  @callback list :: {:ok, [map]}
  @callback list_by_date(binary) :: {:ok, [map]} | {:error, term}
  @callback clear :: :ok
end

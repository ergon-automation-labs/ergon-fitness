defmodule BotArmyFitness.GoalStoreBehaviour do
  @moduledoc """
  Behaviour for GoalStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback get(binary, binary) :: map | nil
  @callback list(binary) :: [map]
  @callback clear :: :ok
end

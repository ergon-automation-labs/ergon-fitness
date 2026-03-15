defmodule BotArmyFitness.GoalStoreBehaviour do
  @moduledoc """
  Behaviour for GoalStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback get(binary) :: map | nil
  @callback list :: [map]
  @callback clear :: :ok
end

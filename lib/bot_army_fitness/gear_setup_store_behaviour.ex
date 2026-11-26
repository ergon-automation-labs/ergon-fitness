defmodule BotArmyFitness.GearSetupStoreBehaviour do
  @moduledoc """
  Behaviour for GearSetupStore so the handlers can be tested without a database.
  """

  @callback get(binary) :: {:ok, String.t()}
  @callback put(binary, String.t()) :: {:ok, String.t()} | {:error, term}
end

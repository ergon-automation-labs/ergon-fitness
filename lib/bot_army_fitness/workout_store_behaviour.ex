defmodule BotArmyFitness.WorkoutStoreBehaviour do
  @moduledoc """
  Behaviour definition for workout storage.

  Allows different implementations (real database, mock) to be swapped via configuration.
  """

  @callback create(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback update(workout_id :: String.t(), payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback get(workout_id :: String.t()) :: {:ok, map()} | {:error, atom()}
  @callback list() :: {:ok, list(map())}
  @callback list_by_date(date_str :: String.t()) :: {:ok, list(map())}
  @callback clear() :: :ok
end

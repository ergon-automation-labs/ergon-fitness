defmodule BotArmyFitness.GearSetupStore do
  @moduledoc """
  Where the cable machine stands, as one row per house.

  `BotArmyFitness.Gear` decides what a position *means* — which movements it can do — and
  this module only keeps the position itself. The two are separate for the same reason
  the catalog and the store are: the rule is testable without a database, and the store
  is replaceable without the rule moving.

  ## A read that fails is not a floor day

  `get/1` answers `"floor"` when the house has never set anything, because that is the
  state the catalog says the room is usually in. It does **not** answer `"floor"` when the
  database cannot be reached: it raises, and the caller (`CoachTodayHandler`) turns that
  into `:read_failed`. An outage that looked like "the cable is on the floor" would
  silently rewrite today's session into a different workout, which is a wrong answer
  rather than a missing one.

  ## A write is not a log

  `put/2` overwrites the row in place. There is no history, because raising and lowering a
  cable is not an event worth keeping — the room's present state is the whole fact. Two
  writes in the same second leave one row, and that is correct.
  """

  @behaviour BotArmyFitness.GearSetupStoreBehaviour

  require Logger

  alias BotArmyFitness.Gear
  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.GearSetup

  @doc """
  The position the cable machine is in, `{:ok, "floor" | "wall"}`.

  Raises if the database cannot be read, which is the caller's signal that the room's
  state is unknown rather than default.
  """
  @impl true
  def get(tenant_id) when is_binary(tenant_id) do
    case Repo.get_by(GearSetup, tenant_id: tenant_id) do
      nil -> {:ok, List.first(Gear.positions())}
      %GearSetup{maxpro: position} when position in ~w(floor wall) -> {:ok, position}
      # A row written before a position existed, or by hand: the rule's own list decides
      # what a plan can read, so an unknown word is refused rather than trusted.
      %GearSetup{maxpro: other} -> {:error, {:unknown_position, other}}
    end
  end

  @doc """
  Put the cable machine in `position`, replacing whatever the row said before.

  Returns `{:ok, position}` so a caller can answer with the state it just wrote instead of
  re-reading it, or `{:error, :bad_position}` for a word the catalog does not know.
  """
  @impl true
  def put(tenant_id, position)
      when is_binary(tenant_id) and position in ~w(floor wall) do
    changeset =
      GearSetup.changeset(
        %GearSetup{id: Ecto.UUID.generate()},
        %{"tenant_id" => tenant_id, "maxpro" => position}
      )

    case Repo.insert(changeset,
           on_conflict: [set: [maxpro: position, updated_at: now()]],
           conflict_target: :tenant_id
         ) do
      {:ok, %GearSetup{maxpro: written}} ->
        Logger.info("The cable machine is set up at the #{written}")
        {:ok, written}

      {:error, changeset} ->
        Logger.error("Failed to record the room's setup: #{inspect(changeset.errors)}")
        {:error, :database_error}
    end
  end

  def put(_tenant_id, _position), do: {:error, :bad_position}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end

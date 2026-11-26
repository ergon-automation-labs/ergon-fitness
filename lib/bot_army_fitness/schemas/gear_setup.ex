defmodule BotArmyFitness.Schemas.GearSetup do
  @moduledoc """
  One row: where the cable machine is set up.

  `maxpro` is the catalog's word for the position (`"floor"` or `"wall"`), validated here
  against `BotArmyFitness.Gear.positions/0` rather than re-typed — the same rule
  `Schemas.WorkoutSet` follows for the movement vocabulary. A column that agreed with
  nothing would let a row say `"basement"` and every plan built from it would read the
  room's state as something the room cannot be.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BotArmyFitness.Gear

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "gear_setups" do
    field(:tenant_id, Ecto.UUID)
    field(:maxpro, :string)

    timestamps()
  end

  @doc false
  def changeset(gear_setup, attrs) do
    gear_setup
    |> cast(attrs, [:tenant_id, :maxpro])
    |> validate_required([:tenant_id, :maxpro])
    |> validate_inclusion(:maxpro, Gear.positions())
    |> unique_constraint(:tenant_id)
  end
end

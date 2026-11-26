defmodule BotArmyFitness.Repo.Migrations.CreateGearSetups do
  @moduledoc """
  How the cable machine is set up: one row per house, and it is a fact, not a log.

  The MaxPRO can stand on the floor or on its wall attachment, and which one it is decides
  half of the movement menu (`BotArmyFitness.Gear`). The catalog carried that as prose
  ("a wall attachment exists for it, but it is set up on the floor most of the time"),
  which is enough for a person reading the menu and not enough for a plan that has to
  choose a movement: prose cannot be pressed.

  So it becomes a row. One row per tenant, overwritten in place — **no history**, because
  this is not an event, it is the state of a room. A person who raises the cable to the
  wall and puts it back an hour later did not perform two actions worth keeping; they
  moved a piece of equipment.

  `maxpro` holds the catalog's own word (`"floor"` / `"wall"`), not a boolean, so the door
  that writes it validates the same list the plan reads and a third position would be a
  migration rather than a mystery string. The bell needs no column: `Gear` reads its
  setting off her newest kettlebell set, which is the only place it is ever recorded.
  """

  use Ecto.Migration

  def change do
    create table(:gear_setups, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:tenant_id, :uuid, null: false)
      add(:maxpro, :string, null: false)

      timestamps()
    end

    create(unique_index(:gear_setups, [:tenant_id]))
  end
end

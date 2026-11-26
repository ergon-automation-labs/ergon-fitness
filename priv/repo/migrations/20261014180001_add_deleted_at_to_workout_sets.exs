defmodule BotArmyFitness.Repo.Migrations.AddDeletedAtToWorkoutSets do
  @moduledoc """
  A set she recorded by mistake has to be takable-back, so a set gets a way to end.

  The pocket records a set with one press. One press has no confirmation step, which is
  the right shape for the glass in her hand and the wrong shape for an irreversible fact:
  a fat-fingered thumb would otherwise leave a number in her progression that she never
  lifted, and every later "next time" line would be built on it.

  So a delete is a **soft** delete. The row keeps its amount and its load and gains a
  `deleted_at`; every read filters it out, so the progression, the day count and the bell's
  setting all behave as if it never happened. Hard-deleting would also work for today's
  reads, but it would throw away the only evidence that the press happened at all, and a
  soft delete is what lets the same press be undone twice without a second row.
  """

  use Ecto.Migration

  def change do
    alter table(:workout_sets) do
      add(:deleted_at, :utc_datetime_usec)
    end

    # Partial index: every read asks for the live rows, and a deleted row is never
    # asked for by anything but an audit.
    create(index(:workout_sets, [:tenant_id, :date], where: "deleted_at IS NULL"))
  end
end

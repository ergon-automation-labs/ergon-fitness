defmodule BotArmyFitness.Repo.Migrations.AddTenantAndUserId do
  use Ecto.Migration

  def up do
    default_tenant_id = "00000000-0000-0000-0000-000000000001"

    # Add tenant_id and user_id to workouts (idempotent)
    unless Ecto.Migration.column_exists?(:workouts, :tenant_id) do
      alter table(:workouts) do
        add(:tenant_id, :uuid, null: true)
        add(:user_id, :uuid, null: true)
      end

      create(index(:workouts, [:tenant_id]))
      create(index(:workouts, [:user_id]))

      execute(
        "UPDATE workouts SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL"
      )
    end

    # Add tenant_id and user_id to goals (idempotent)
    unless Ecto.Migration.column_exists?(:goals, :tenant_id) do
      alter table(:goals) do
        add(:tenant_id, :uuid, null: true)
        add(:user_id, :uuid, null: true)
      end

      create(index(:goals, [:tenant_id]))
      create(index(:goals, [:user_id]))

      execute(
        "UPDATE goals SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL"
      )
    end
  end

  def down do
    # Drop indexes and columns for workouts
    drop(index(:workouts, [:tenant_id])) if Ecto.Migration.index_exists?(:workouts, [:tenant_id])
    drop(index(:workouts, [:user_id])) if Ecto.Migration.index_exists?(:workouts, [:user_id])

    alter table(:workouts) do
      remove(:tenant_id) if Ecto.Migration.column_exists?(:workouts, :tenant_id)
      remove(:user_id) if Ecto.Migration.column_exists?(:workouts, :user_id)
    end

    # Drop indexes and columns for goals
    drop(index(:goals, [:tenant_id])) if Ecto.Migration.index_exists?(:goals, [:tenant_id])
    drop(index(:goals, [:user_id])) if Ecto.Migration.index_exists?(:goals, [:user_id])

    alter table(:goals) do
      remove(:tenant_id) if Ecto.Migration.column_exists?(:goals, :tenant_id)
      remove(:user_id) if Ecto.Migration.column_exists?(:goals, :user_id)
    end
  end
end

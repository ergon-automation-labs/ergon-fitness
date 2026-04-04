defmodule BotArmyFitness.Repo.Migrations.AddTenantAndUserId do
  use Ecto.Migration

  def up do
    # workouts table
    alter table(:workouts) do
      add :tenant_id, :uuid, null: true
      add :user_id, :uuid, null: true
    end
    create index(:workouts, [:tenant_id])
    create index(:workouts, [:user_id])

    # goals table
    alter table(:goals) do
      add :tenant_id, :uuid, null: true
      add :user_id, :uuid, null: true
    end
    create index(:goals, [:tenant_id])
    create index(:goals, [:user_id])

    # Backfill all rows with default tenant UUID
    default_tenant_id = "00000000-0000-0000-0000-000000000001"
    execute("""
    UPDATE workouts SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL
    """)
    execute("""
    UPDATE goals SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL
    """)
  end

  def down do
    # workouts table
    drop index(:workouts, [:tenant_id])
    drop index(:workouts, [:user_id])
    alter table(:workouts) do
      remove :tenant_id
      remove :user_id
    end

    # goals table
    drop index(:goals, [:tenant_id])
    drop index(:goals, [:user_id])
    alter table(:goals) do
      remove :tenant_id
      remove :user_id
    end
  end
end

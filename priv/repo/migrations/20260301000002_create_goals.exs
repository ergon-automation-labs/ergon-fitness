defmodule BotArmyFitness.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :target_date, :date, null: false
      add :status, :string, default: "active", null: false

      timestamps()
    end

    create index(:goals, [:status])
    create index(:goals, [:target_date])
  end
end

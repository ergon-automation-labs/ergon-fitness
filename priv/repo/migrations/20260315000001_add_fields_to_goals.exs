defmodule BotArmyFitness.Repo.Migrations.AddFieldsToGoals do
  use Ecto.Migration

  def change do
    alter table(:goals) do
      add :goal_type, :string
      add :target_value, :string
    end

    create index(:goals, [:goal_type])
  end
end

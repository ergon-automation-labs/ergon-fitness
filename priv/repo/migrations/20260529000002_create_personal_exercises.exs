defmodule BotArmyFitness.Repo.Migrations.CreatePersonalExercises do
  use Ecto.Migration

  def change do
    create table(:personal_exercises) do
      add(:tenant_id, :string, null: false)
      add(:name, :string, null: false)
      add(:equipment_type, :string, null: false)
      add(:notes, :text)
      add(:last_used_at, :utc_datetime)
      timestamps()
    end

    create(unique_index(:personal_exercises, [:tenant_id, :name]))
    create(index(:personal_exercises, [:tenant_id, :equipment_type]))
  end
end

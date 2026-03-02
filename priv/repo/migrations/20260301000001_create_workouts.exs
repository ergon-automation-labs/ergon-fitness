defmodule BotArmyFitness.Repo.Migrations.CreateWorkouts do
  use Ecto.Migration

  def change do
    create table(:workouts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :date, :date, null: false
      add :duration_minutes, :integer, null: false
      add :exercise_type, :string, null: false
      add :intensity, :string, default: "moderate", null: false
      add :calories, :integer
      add :location, :string

      timestamps()
    end

    create index(:workouts, [:date])
    create index(:workouts, [:exercise_type])
    create index(:workouts, [:intensity])
  end
end

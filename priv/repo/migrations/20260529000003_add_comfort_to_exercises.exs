defmodule BotArmyFitness.Repo.Migrations.AddComfortToExercises do
  use Ecto.Migration

  def change do
    alter table(:personal_exercises) do
      add(:comfort_level, :float, default: 5.0)
      add(:last_performed_at, :utc_datetime)
      add(:times_performed, :integer, default: 0)
    end

    create(index(:personal_exercises, [:comfort_level]))
  end
end

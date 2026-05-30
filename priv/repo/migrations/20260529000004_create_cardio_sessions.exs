defmodule BotArmyFitness.Repo.Migrations.CreateCardioSessions do
  use Ecto.Migration

  def change do
    create table(:cardio_sessions) do
      add(:tenant_id, :string, null: false)
      add(:activity_type, :string, null: false)
      add(:duration_minutes, :integer, null: false)
      add(:distance_miles, :float, null: false)
      add(:pace_per_mile, :float)
      add(:comfort_level, :float, default: 5.0)
      add(:notes, :text)
      add(:streak_days, :integer, default: 0)
      add(:session_date, :date, null: false)
      timestamps()
    end

    create(index(:cardio_sessions, [:tenant_id, :session_date]))
    create(index(:cardio_sessions, [:tenant_id, :activity_type]))
    create(index(:cardio_sessions, [:comfort_level]))
  end
end

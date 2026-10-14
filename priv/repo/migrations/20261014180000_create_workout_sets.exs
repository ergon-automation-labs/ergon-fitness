defmodule BotArmyFitness.Repo.Migrations.CreateWorkoutSets do
  @moduledoc """
  One row per set: what movement, how much of it, and under what load.

  This table exists because a movement is not a workout. `workouts` records a
  session in the vocabulary of a session — how long, how hard — and neither of
  those columns can say "24.5 kg, 12 reps". A home-gym progression lives in the
  second sentence, so it gets its own row rather than two invented numbers in the
  first.
  """

  use Ecto.Migration

  def change do
    create table(:workout_sets, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:exercise, :string, null: false)
      add(:measure, :string, null: false)
      add(:amount, :integer, null: false)
      add(:load_kind, :string, null: false)
      add(:load_value, :float)
      add(:date, :date, null: false)
      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps()
    end

    create(index(:workout_sets, [:date]))
    create(index(:workout_sets, [:exercise]))
    create(index(:workout_sets, [:tenant_id]))
  end
end

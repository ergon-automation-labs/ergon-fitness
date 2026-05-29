defmodule BotArmyFitness.Schemas.PersonalExercise do
  use Ecto.Schema

  schema "personal_exercises" do
    field(:tenant_id, :string)
    field(:name, :string)
    field(:equipment_type, :string)
    field(:notes, :string)
    field(:last_used_at, :utc_datetime)
    field(:comfort_level, :float, default: 5.0)
    field(:last_performed_at, :utc_datetime)
    field(:times_performed, :integer, default: 0)

    timestamps()
  end
end

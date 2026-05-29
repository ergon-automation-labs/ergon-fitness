defmodule BotArmyFitness.Schemas.PersonalExercise do
  use Ecto.Schema

  schema "personal_exercises" do
    field(:tenant_id, :string)
    field(:name, :string)
    field(:equipment_type, :string)
    field(:notes, :string)
    field(:last_used_at, :utc_datetime)

    timestamps()
  end
end

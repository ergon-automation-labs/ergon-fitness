defmodule BotArmyFitness.Schemas.CardioSession do
  use Ecto.Schema

  schema "cardio_sessions" do
    field(:tenant_id, :string)
    field(:activity_type, :string)
    field(:duration_minutes, :integer)
    field(:distance_miles, :float)
    field(:pace_per_mile, :float)
    field(:comfort_level, :float, default: 5.0)
    field(:notes, :string)
    field(:streak_days, :integer, default: 0)
    field(:session_date, :date)

    timestamps()
  end
end

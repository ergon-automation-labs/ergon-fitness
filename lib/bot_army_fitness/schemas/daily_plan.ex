defmodule BotArmyFitness.Schemas.DailyPlan do
  use Ecto.Schema

  schema "daily_plans" do
    field(:tenant_id, :string)
    field(:date, :date)
    field(:type, :string)
    field(:estimated_minutes, :integer)
    field(:motivational_quote, :string)
    field(:video_url, :string)
    field(:exercises, {:array, :map})
    field(:notes, :string)
    field(:plan_json, :map)
    field(:generated_at, :utc_datetime)

    timestamps()
  end
end

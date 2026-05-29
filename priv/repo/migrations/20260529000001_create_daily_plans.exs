defmodule BotArmyFitness.Repo.Migrations.CreateDailyPlans do
  use Ecto.Migration

  def change do
    create table(:daily_plans) do
      add(:tenant_id, :string, null: false)
      add(:date, :date, null: false)
      add(:type, :string, null: false)
      add(:estimated_minutes, :integer)
      add(:motivational_quote, :text)
      add(:video_url, :string)
      add(:exercises, :jsonb)
      add(:notes, :text)
      add(:plan_json, :jsonb, null: false)
      add(:generated_at, :utc_datetime)
      timestamps()
    end

    create(unique_index(:daily_plans, [:tenant_id, :date]))
  end
end

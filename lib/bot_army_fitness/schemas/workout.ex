defmodule BotArmyFitness.Schemas.Workout do
  @moduledoc """
  Ecto schema for fitness workouts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "workouts" do
    field :title, :string
    field :date, :date
    field :duration_minutes, :integer
    field :exercise_type, :string
    field :intensity, :string, default: "moderate"
    field :calories, :integer
    field :location, :string
    field :tenant_id, Ecto.UUID
    field :user_id, Ecto.UUID

    timestamps()
  end

  @doc false
  def changeset(workout, attrs) do
    workout
    |> cast(attrs, [:title, :date, :duration_minutes, :exercise_type, :intensity, :calories, :location, :tenant_id, :user_id])
    |> validate_required([:title, :date, :exercise_type])
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:calories, greater_than_or_equal_to: 0)
    |> validate_inclusion(:intensity, ["light", "moderate", "high", "very_high"])
    |> validate_inclusion(:exercise_type, ["running", "cycling", "strength", "cardio", "stretching", "yoga", "swimming", "sports", "other"])
  end
end

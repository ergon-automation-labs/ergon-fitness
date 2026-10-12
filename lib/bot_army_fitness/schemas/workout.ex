defmodule BotArmyFitness.Schemas.Workout do
  @moduledoc """
  Ecto schema for fitness workouts.

  The two inclusion lists below are `BotArmyFitness.WorkoutTypes` — the one
  vocabulary — rather than a copy. They were a copy, and they had drifted:
  `intensity` accepted `high` and `very_high` (two words that appear nowhere else
  in the bot, and that no surface sends) and rejected `intense` (the word the
  phone, the rotation plan and the fold all produce), so every log the phone sent
  was refused with `validation: :inclusion` and `exercise_type` rejected
  `walking` and `hiit`, which are in the picker. Referencing the module means the
  column cannot disagree with the vocabulary the bot speaks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BotArmyFitness.WorkoutTypes

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "workouts" do
    field(:title, :string)
    field(:date, :date)
    field(:duration_minutes, :integer)
    field(:exercise_type, :string)
    field(:intensity, :string, default: "moderate")
    field(:calories, :integer)
    field(:location, :string)
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  @doc false
  def changeset(workout, attrs) do
    workout
    |> cast(attrs, [
      :title,
      :date,
      :duration_minutes,
      :exercise_type,
      :intensity,
      :calories,
      :location,
      :tenant_id,
      :user_id
    ])
    |> validate_required([:title, :date, :exercise_type, :tenant_id])
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:calories, greater_than_or_equal_to: 0)
    |> validate_inclusion(:intensity, WorkoutTypes.intensities())
    |> validate_inclusion(:exercise_type, WorkoutTypes.values())
  end
end

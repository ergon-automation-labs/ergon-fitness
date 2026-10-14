defmodule BotArmyFitness.Schemas.WorkoutSet do
  @moduledoc """
  Ecto schema for one set of one movement: the load and the reps.

  A set is the unit a home gym actually progresses in. It is **not** a workout
  row with two extra columns, because the two answer different questions: a
  workout says how long a session was, and a set says what she lifted. The
  `workouts` table's `duration_minutes` is `null: false`, so a set forced into it
  would have to invent a length — which is precisely the defect this table
  removes.

  ## The vocabulary is the catalog's, not a copy

  `measure` and `load_kind` are the values `BotArmyFitness.ExerciseCatalog` puts
  on a movement and its equipment (`"reps"`/`"seconds"`, `"kg"`/`"level"`/
  `"bodyweight"`). The columns are validated against that module's lists rather
  than re-typed here, the same rule `Schemas.Workout` follows for
  `WorkoutTypes`: a column that disagrees with the vocabulary the bot speaks
  refuses writes the bot itself would make.

  `load_value` is kilograms or the device's own resistance level, never both and
  never a converted guess — the MaxPRO's `"level"` is a PowerClutch position, not
  a weight stack, and storing its 12 as 12 kg would be inventing a number the
  device never showed. The kind travels with the number so a reader never has to
  guess which scale it is on. For `"bodyweight"` the number is optional and means
  load *added* (a belt) or *taken away* (an assist), which is why it may be
  negative.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BotArmyFitness.ExerciseCatalog

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "workout_sets" do
    field(:exercise, :string)
    field(:measure, :string)
    field(:amount, :integer)
    field(:load_kind, :string)
    field(:load_value, :float)
    field(:date, :date)
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  @doc false
  def changeset(workout_set, attrs) do
    workout_set
    |> cast(attrs, [
      :exercise,
      :measure,
      :amount,
      :load_kind,
      :load_value,
      :date,
      :tenant_id,
      :user_id
    ])
    |> validate_required([:exercise, :measure, :amount, :load_kind, :date, :tenant_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:measure, ExerciseCatalog.measures())
    |> validate_inclusion(:load_kind, ExerciseCatalog.load_kinds())
  end
end

defmodule BotArmyFitness.Schemas.Goal do
  @moduledoc """
  Ecto schema for fitness goals.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "goals" do
    field :title, :string
    field :target_date, :date
    field :status, :string, default: "active"
    field :goal_type, :string
    field :target_value, :string

    timestamps()
  end

  @doc false
  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:title, :target_date, :status, :goal_type, :target_value])
    |> validate_required([:title, :target_date, :goal_type])
    |> validate_inclusion(:status, ["active", "completed", "archived"])
  end
end

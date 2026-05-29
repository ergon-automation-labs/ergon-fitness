defmodule BotArmyFitness.PersonalExerciseStore do
  require Logger
  import Ecto.Query
  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.PersonalExercise

  def list_by_equipment(tenant_id, equipment_type) do
    Repo.all(
      from(pe in PersonalExercise,
        where: pe.tenant_id == ^tenant_id and pe.equipment_type == ^equipment_type,
        order_by: [desc: :last_used_at, asc: :name]
      )
    )
  end

  def list_all(tenant_id) do
    Repo.all(
      from(pe in PersonalExercise,
        where: pe.tenant_id == ^tenant_id,
        order_by: [desc: :last_used_at, asc: :name]
      )
    )
  end

  def create_or_update(tenant_id, name, equipment_type, notes \\ nil) do
    existing = Repo.get_by(PersonalExercise, tenant_id: tenant_id, name: name)

    attrs = %{
      tenant_id: tenant_id,
      name: name,
      equipment_type: equipment_type,
      notes: notes,
      last_used_at: DateTime.utc_now()
    }

    case existing do
      nil ->
        PersonalExercise
        |> Ecto.Changeset.cast(attrs, [:tenant_id, :name, :equipment_type, :notes, :last_used_at])
        |> Repo.insert()

      ex ->
        ex
        |> Ecto.Changeset.cast(attrs, [:equipment_type, :notes, :last_used_at])
        |> Repo.update()
    end
    |> case do
      {:ok, exercise} ->
        Logger.info("[PersonalExerciseStore] Saved #{name} (#{equipment_type}) for #{tenant_id}")

        {:ok, exercise}

      {:error, changeset} ->
        Logger.error(
          "[PersonalExerciseStore] Error saving exercise: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  def to_response(exercise) do
    %{
      "id" => to_string(exercise.id),
      "name" => exercise.name,
      "equipment_type" => exercise.equipment_type,
      "notes" => exercise.notes,
      "last_used_at" => DateTime.to_iso8601(exercise.last_used_at)
    }
  end
end

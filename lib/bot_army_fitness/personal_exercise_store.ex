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

  def update_comfort(tenant_id, name, reps_achieved, reps_target, user_rating \\ nil) do
    case Repo.get_by(PersonalExercise, tenant_id: tenant_id, name: name) do
      nil ->
        {:error, :not_found}

      exercise ->
        # Auto-adjust comfort based on performance
        auto_adjust =
          cond do
            reps_achieved >= reps_target -> 0.5
            reps_achieved >= reps_target - 1 -> 0.2
            reps_achieved >= reps_target - 2 -> 0.0
            true -> -0.5
          end

        # User manual rating (1-10 scale) blended with auto-adjust
        final_comfort =
          if user_rating && user_rating > 0 do
            # Weight user rating 60%, auto-adjust 40%
            (user_rating * 0.6 + (5 + auto_adjust) * 0.4) / 10 * 10
          else
            exercise.comfort_level + auto_adjust
          end

        # Clamp to 1-10
        final_comfort = max(1.0, min(10.0, final_comfort))

        attrs = %{
          comfort_level: final_comfort,
          last_performed_at: DateTime.utc_now(),
          times_performed: (exercise.times_performed || 0) + 1
        }

        exercise
        |> Ecto.Changeset.cast(attrs, [:comfort_level, :last_performed_at, :times_performed])
        |> Repo.update()
    end
  end

  def to_response(exercise) do
    %{
      "id" => to_string(exercise.id),
      "name" => exercise.name,
      "equipment_type" => exercise.equipment_type,
      "notes" => exercise.notes,
      "comfort_level" => exercise.comfort_level || 5.0,
      "last_used_at" => DateTime.to_iso8601(exercise.last_used_at),
      "times_performed" => exercise.times_performed || 0
    }
  end
end

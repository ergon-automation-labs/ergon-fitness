defmodule BotArmyFitness.Handlers.PersonalExercisesHandler do
  require Logger
  alias BotArmyFitness.PersonalExerciseStore

  def handle_list_by_equipment(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}
    equipment_type = payload["equipment_type"]

    if equipment_type do
      exercises = PersonalExerciseStore.list_by_equipment(tenant_id, equipment_type)

      Logger.info(
        "[PersonalExercisesHandler] Listed #{length(exercises)} exercises for #{equipment_type}"
      )

      %{
        "exercises" => Enum.map(exercises, &PersonalExerciseStore.to_response/1),
        "count" => length(exercises)
      }
    else
      %{"error" => "missing_equipment_type"}
    end
  end

  def handle_save_exercise(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}

    with name <- payload["name"],
         equipment_type <- payload["equipment_type"],
         true <- name && equipment_type do
      notes = payload["notes"]

      case PersonalExerciseStore.create_or_update(tenant_id, name, equipment_type, notes) do
        {:ok, exercise} ->
          %{"ok" => true, "exercise" => PersonalExerciseStore.to_response(exercise)}

        {:error, _changeset} ->
          %{"ok" => false, "error" => "failed_to_save"}
      end
    else
      _ -> %{"error" => "missing_name_or_equipment_type"}
    end
  end
end

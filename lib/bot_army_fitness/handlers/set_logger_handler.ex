defmodule BotArmyFitness.Handlers.SetLoggerHandler do
  require Logger
  alias BotArmyFitness.PersonalExerciseStore

  def handle_log_set(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}

    with exercise_name <- payload["exercise_name"],
         reps_achieved <- payload["reps_achieved"],
         reps_target <- payload["reps_target"],
         true <- exercise_name && reps_achieved && reps_target do
      user_rating = payload["comfort_rating"]

      case PersonalExerciseStore.update_comfort(
             tenant_id,
             exercise_name,
             reps_achieved,
             reps_target,
             user_rating
           ) do
        {:ok, exercise} ->
          Logger.info(
            "[SetLoggerHandler] Updated comfort for #{exercise_name}: #{exercise.comfort_level}/10"
          )

          %{
            "ok" => true,
            "exercise" => PersonalExerciseStore.to_response(exercise)
          }

        {:error, :not_found} ->
          %{"ok" => false, "error" => "exercise_not_found"}

        {:error, _changeset} ->
          %{"ok" => false, "error" => "failed_to_update"}
      end
    else
      _ -> %{"error" => "missing_required_fields"}
    end
  end
end

defmodule BotArmyFitness.Handlers.CardioHandler do
  require Logger
  alias BotArmyFitness.CardioSessionStore

  def handle_log_cardio(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}

    with activity_type <- payload["activity_type"],
         duration_minutes <- payload["duration_minutes"],
         distance_miles <- payload["distance_miles"],
         true <- activity_type && duration_minutes && distance_miles do
      comfort_rating = payload["comfort_rating"]
      notes = payload["notes"]

      case CardioSessionStore.log_session(
             tenant_id,
             activity_type,
             duration_minutes,
             distance_miles,
             comfort_rating,
             notes
           ) do
        {:ok, session} ->
          Logger.info("[CardioHandler] Logged #{activity_type} session")

          %{
            "ok" => true,
            "session" => CardioSessionStore.to_response(session)
          }

        {:error, _changeset} ->
          %{"ok" => false, "error" => "failed_to_log"}
      end
    else
      _ -> %{"error" => "missing_required_fields"}
    end
  end
end

defmodule BotArmyFitness.Handlers.TodayPlanHandler do
  require Logger
  alias BotArmyFitness.DailyPlanStore

  def handle_request(message) do
    %{tenant_id: tenant_id} = BotArmyCore.Tenant.extract_context(message)

    case DailyPlanStore.get_today(tenant_id) do
      {:ok, plan} ->
        Logger.info("[TodayPlanHandler] Returning plan for #{tenant_id}")
        DailyPlanStore.to_response(plan)

      {:error, :not_found} ->
        Logger.info("[TodayPlanHandler] No plan for #{tenant_id} today")
        %{"ok" => false, "error" => "no_plan_found"}
    end
  end
end

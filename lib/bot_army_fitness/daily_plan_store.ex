defmodule BotArmyFitness.DailyPlanStore do
  require Logger
  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.DailyPlan

  def get_today(tenant_id) do
    today = Date.utc_today()

    case Repo.get_by(DailyPlan, tenant_id: tenant_id, date: today) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  def create_plan(tenant_id, plan_data) do
    today = Date.utc_today()

    plan_attrs = %{
      tenant_id: tenant_id,
      date: today,
      type: plan_data["type"],
      estimated_minutes: plan_data["estimated_minutes"],
      motivational_quote: plan_data["motivational_quote"],
      video_url: plan_data["video_url"],
      exercises: plan_data["exercises"],
      notes: plan_data["notes"],
      plan_json: plan_data,
      generated_at: DateTime.utc_now()
    }

    case Repo.insert_or_update_by(
           DailyPlan,
           [tenant_id: tenant_id, date: today],
           plan_attrs
         ) do
      {:ok, plan} ->
        Logger.info("[DailyPlanStore] Created/updated plan for #{tenant_id} on #{today}")
        {:ok, plan}

      {:error, changeset} ->
        Logger.error("[DailyPlanStore] Error storing plan: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def to_response(plan) do
    %{
      "id" => to_string(plan.id),
      "date" => Date.to_string(plan.date),
      "type" => plan.type,
      "estimated_minutes" => plan.estimated_minutes,
      "motivational_quote" => plan.motivational_quote,
      "video_url" => plan.video_url,
      "exercises" => plan.exercises || [],
      "notes" => plan.notes,
      "generated_at" => DateTime.to_iso8601(plan.generated_at)
    }
  end
end

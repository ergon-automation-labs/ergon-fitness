defmodule BotArmyFitness.CardioSessionStore do
  @moduledoc "Logs cardio sessions and calculates comfort/streak based on pace and consistency."

  require Logger
  import Ecto.Query
  alias BotArmyFitness.Repo
  alias BotArmyFitness.Schemas.CardioSession

  def log_session(
        tenant_id,
        activity_type,
        duration_minutes,
        distance_miles,
        comfort_rating \\ nil,
        notes \\ nil
      ) do
    today = Date.utc_today()
    pace_per_mile = distance_miles / (duration_minutes / 60.0)

    # Auto-adjust comfort based on pace/distance consistency
    auto_comfort = calculate_auto_comfort(tenant_id, activity_type, pace_per_mile)

    final_comfort =
      if comfort_rating && comfort_rating > 0 do
        # Blend user rating 60% + auto-adjust 40%
        (comfort_rating * 0.6 + auto_comfort * 0.4) |> Float.round(1)
      else
        auto_comfort |> Float.round(1)
      end

    final_comfort = max(1.0, min(10.0, final_comfort))

    # Calculate streak
    streak = calculate_streak(tenant_id, today)

    attrs = %{
      tenant_id: tenant_id,
      activity_type: activity_type,
      duration_minutes: duration_minutes,
      distance_miles: distance_miles,
      pace_per_mile: pace_per_mile |> Float.round(2),
      comfort_level: final_comfort,
      notes: notes,
      streak_days: streak,
      session_date: today
    }

    case Repo.insert(Ecto.Changeset.cast(CardioSession, attrs, Map.keys(attrs))) do
      {:ok, session} ->
        Logger.info(
          "[CardioSessionStore] Logged #{activity_type}: #{distance_miles} mi in #{duration_minutes} min (comfort: #{final_comfort}/10, streak: #{streak}d)"
        )

        {:ok, session}

      {:error, changeset} ->
        Logger.error("[CardioSessionStore] Error logging session: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp calculate_auto_comfort(tenant_id, activity_type, current_pace) do
    # Get recent sessions of same type
    recent =
      Repo.all(
        from(cs in CardioSession,
          where: cs.tenant_id == ^tenant_id and cs.activity_type == ^activity_type,
          order_by: [desc: :session_date],
          limit: 5
        )
      )

    case recent do
      [] ->
        # Default neutral
        5.0

      sessions ->
        paces = Enum.map(sessions, & &1.pace_per_mile)
        avg_pace = Enum.sum(paces) / length(sessions)

        cond do
          # Faster = easier
          current_pace < avg_pace * 0.95 -> 7.0
          # Slower = harder
          current_pace > avg_pace * 1.05 -> 3.0
          # Similar pace = moderate
          true -> 5.0
        end
    end
  end

  defp calculate_streak(tenant_id, today) do
    # Count consecutive days of activity (including today)
    last_week = Date.add(today, -7)

    sessions =
      Repo.all(
        from(cs in CardioSession,
          where: cs.tenant_id == ^tenant_id and cs.session_date > ^last_week,
          select: cs.session_date,
          order_by: [desc: :session_date]
        )
      )

    case sessions do
      [] -> 1
      dates -> count_consecutive_days(Enum.uniq(dates), today, 0)
    end
  end

  defp count_consecutive_days([date | rest], current, acc) do
    if Date.diff(current, date) <= 1 do
      count_consecutive_days(rest, date, acc + 1)
    else
      acc + 1
    end
  end

  defp count_consecutive_days([], _current, acc), do: acc

  def get_activity_comfort(tenant_id, activity_type) do
    case Repo.one(
           from(cs in CardioSession,
             where: cs.tenant_id == ^tenant_id and cs.activity_type == ^activity_type,
             select: avg(cs.comfort_level),
             limit: 1
           )
         ) do
      nil -> 5.0
      avg -> avg || 5.0
    end
  end

  def list_recent(tenant_id, days) do
    cutoff = Date.add(Date.utc_today(), -days)

    try do
      sessions =
        Repo.all(
          from(cs in CardioSession,
            where: cs.tenant_id == ^tenant_id and cs.session_date > ^cutoff,
            order_by: [desc: :session_date]
          )
        )

      {:ok, Enum.map(sessions, &to_response/1)}
    rescue
      _ -> {:error, :query_failed}
    end
  end

  def to_response(session) do
    %{
      "id" => to_string(session.id),
      "activity_type" => session.activity_type,
      "duration_minutes" => session.duration_minutes,
      "distance_miles" => session.distance_miles,
      "pace_per_mile" => session.pace_per_mile,
      "comfort_level" => session.comfort_level,
      "streak_days" => session.streak_days,
      "session_date" => Date.to_string(session.session_date),
      "notes" => session.notes
    }
  end
end

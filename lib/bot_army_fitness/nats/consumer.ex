defmodule BotArmyFitness.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the Fitness bot.

  Subscribes to NATS subjects matching Fitness message patterns:
  - `fitness.workout.*` - Workout-related events
  - `fitness.goal.*` - Fitness goal events

  Messages are decoded using BotArmyCore.NATS.Decoder and routed to
  appropriate handlers based on the event type.

  ## Features

  - Automatic subscription to Fitness topics
  - Message decoding and validation
  - Event-based routing to handlers
  - Graceful error handling and recovery
  - Comprehensive logging

  ## Connection Management

  The consumer maintains a persistent NATS connection. If the connection
  is lost, it will attempt to reconnect with exponential backoff.
  """

  use GenServer
  require Logger
  alias BotArmyRuntime.Registry

  @reconnect_delay_ms 5000
  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000

  @subjects [
    %{subject: "fitness.workout.log", type: :subscribe, description: "Log workout"},
    %{subject: "fitness.goal.set", type: :subscribe, description: "Set fitness goal"},
    %{subject: "fitness.goal.update", type: :subscribe, description: "Update fitness goal"},
    %{subject: "fitness.goal.progress", type: :subscribe, description: "Report goal progress"},
    %{
      subject: "fitness.workout.plan.request",
      type: :request_reply,
      description: "Request workout plan"
    },
    %{
      subject: "fitness.chat",
      type: :request_reply,
      description: "Conversational chat with fitness persona"
    },
    %{
      subject: "fitness.workout.today",
      type: :request_reply,
      description: "Get today's workout plan"
    },
    %{
      subject: "events.llm.response.parsed",
      type: :subscribe,
      description: "LLM response parsed"
    },
    %{
      subject: "bot_army.fitness.intent.suggest_workout",
      type: :subscribe,
      description: "Intent: suggest workout"
    },
    %{
      subject: "discord.check_in.response",
      type: :subscribe,
      description: "Discord check-in response (done/defer)"
    },
    %{
      subject: "gossip.tavern.narrated",
      type: :subscribe,
      description: "Tavern gossip reactions"
    }
  ]

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Fitness NATS consumer")

    state = %{
      subscriptions: [],
      conn: nil,
      opts: opts
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("Connected to NATS, subscribing to fitness topics")

        Enum.each(@subjects, fn %{subject: subject} ->
          Gnat.sub(conn, self(), subject)
          Logger.info("Fitness consumer subscribed to #{subject}")
        end)

        deployment_status =
          Application.get_env(:bot_army_fitness, :deployment_status, "experimental")

        Registry.register("fitness", @subjects, @version, deployment_status)
        Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.warning(
          "Failed to get NATS connection: #{inspect(reason)}, retrying in #{@reconnect_delay_ms}ms"
        )

        Process.send_after(self(), :retry_subscribe, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("Received NATS message on subject: #{msg.topic}")

      case BotArmyCore.NATS.Decoder.decode(msg.body) do
        {:ok, decoded_message} ->
          route_message(decoded_message, msg)

        {:error, reason} ->
          Logger.warning("Failed to decode message from #{msg.topic}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to NATS")
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("Disconnected from NATS, will reconnect")
    Process.send_after(self(), :reconnect, @reconnect_delay_ms)
    {:noreply, %{state | conn: nil, subscriptions: []}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    if state.subscriptions != [] do
      deployment_status =
        Application.get_env(:bot_army_fitness, :deployment_status, "experimental")

      Registry.register("fitness", @subjects, @version, deployment_status)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  # Private functions

  @doc """
  Route decoded message to appropriate handler based on event type.
  """
  def route_message(message, nats_msg) do
    event = message["event"]

    case event do
      "fitness.workout.log" ->
        BotArmyFitness.Handlers.WorkoutHandler.handle_log(message)

      "fitness.goal.set" ->
        BotArmyFitness.Handlers.GoalHandler.handle_set(message)

      "fitness.goal.update" ->
        BotArmyFitness.Handlers.GoalHandler.handle_update(message)

      "fitness.goal.progress" ->
        handle_goal_progress(nats_msg, message)

      "fitness.workout.plan.request" ->
        BotArmyFitness.Handlers.WorkoutPlanHandler.handle_plan_request(message)

      "fitness.chat" ->
        BotArmyFitness.Handlers.ChatHandler.handle_chat(message, nats_msg.reply_to)

      "fitness.workout.today" ->
        response = BotArmyFitness.Handlers.TodayPlanHandler.handle_request(message)

        case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
          {:ok, conn} ->
            Gnat.pub(conn, nats_msg.reply_to, Jason.encode!(response))

          {:error, reason} ->
            Logger.warning("[TodayPlanHandler] Failed to reply: #{inspect(reason)}")
        end

      "llm.response.parsed" ->
        BotArmyFitness.Handlers.WorkoutPlanHandler.handle_llm_response(message)

      "discord.check_in.response" ->
        handle_check_in_response(message)

      "gossip.tavern.narrated" ->
        maybe_react_to_gossip(message)

      _ ->
        Logger.debug("Unknown Fitness event type: #{event}")
    end
  end

  @react_probability 0.10

  defp maybe_react_to_gossip(message) do
    payload = message["payload"] || message || %{}
    source = to_string(payload["source"] || "")
    text = to_string(payload["text"] || "")

    # Remember everything, even if we don't react
    BotArmyFitness.TavernMemory.record_gossip(source, text)

    # Skip self, skip reactions to reactions
    if source == "fitness_bot" or source == "" or is_reaction?(payload) do
      :ok
    else
      if :rand.uniform() < @react_probability do
        reaction = build_reaction(text)
        publish_tavern_reaction(reaction)
      end
    end
  end

  defp is_reaction?(payload) do
    Map.has_key?(payload, "reacting_to") or Map.get(payload, "reaction", false) == true
  end

  defp build_reaction(text) do
    down = String.downcase(text)
    mood = BotArmyFitness.TavernMemory.current_mood()

    # 10% chance to reference earlier chatter
    callback =
      if :rand.uniform() < 0.10 do
        BotArmyFitness.TavernMemory.callback_earlier()
      end

    reaction =
      cond do
        String.contains?(down, "lesson") or String.contains?(down, "study") or
            String.contains?(down, "learning") ->
          "Good time for a walk while that lesson settles."

        String.contains?(down, "workout") or String.contains?(down, "exercise") or
            String.contains?(down, "fitness") ->
          "Another patron keeping the forge hot."

        String.contains?(down, "completed") or String.contains?(down, "done") or
            String.contains?(down, "finished") ->
          "Momentum builds. Don't let it cool."

        String.contains?(down, "failed") or String.contains?(down, "error") or
            String.contains?(down, "broke") ->
          "Even the best iron breaks. Rest, then return."

        String.contains?(down, "proposal") or String.contains?(down, "factory") ->
          "A strong body builds strong systems."

        true ->
          if mood > 0 do
            "The tavern feels alive tonight."
          else
            "The forge is quiet. Too quiet."
          end
      end

    if callback do
      "#{callback} #{reaction}"
    else
      reaction
    end
  end

  defp publish_tavern_reaction(text) do
    payload = %{
      "event" => "gossip.tavern.narrated",
      "source" => "fitness_bot",
      "text" => text,
      "reaction" => true,
      "reacting_to" => "tavern",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case BotArmyRuntime.NATS.Publisher.publish("gossip.tavern.narrated", payload) do
      {:ok, _} -> Logger.info("[Fitness] Tavern reaction: #{text}")
      {:error, reason} -> Logger.warning("[Fitness] Reaction publish failed: #{inspect(reason)}")
    end
  end

  defp handle_goal_progress(nats_msg, message) do
    if nats_msg.reply_to do
      payload = message["payload"] || %{}
      goal_id = payload["goal_id"]
      tenant_id = message["tenant_id"] || BotArmyCore.Tenant.default_tenant_id()

      goal = BotArmyFitness.GoalStore.get(tenant_id, goal_id)

      response =
        case goal do
          nil ->
            %{"error" => "Goal not found"}

          goal_data ->
            workouts_last_30 = count_recent_workouts(tenant_id)
            days_remaining = days_until_target(goal_data["target_date"])

            %{
              "goal" => goal_data,
              "workouts_last_30_days" => workouts_last_30,
              "days_remaining" => days_remaining
            }
        end

      case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
        {:ok, conn} ->
          Gnat.pub(conn, nats_msg.reply_to, Jason.encode!(response))
          Logger.debug("Published goal progress response")

        {:error, reason} ->
          Logger.warning("Failed to publish goal progress: #{inspect(reason)}")
      end
    end
  end

  defp count_recent_workouts(tenant_id) do
    {:ok, workouts} = BotArmyFitness.WorkoutStore.list(tenant_id)
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    Enum.count(workouts, fn w ->
      case NaiveDateTime.from_iso8601(w["created_at"] || "") do
        {:ok, created_naive} ->
          DateTime.compare(DateTime.from_naive!(created_naive, "Etc/UTC"), thirty_days_ago) != :lt

        _ ->
          false
      end
    end)
  end

  defp handle_check_in_response(message) do
    payload = message["payload"] || %{}

    if payload["bot_name"] == "fitness" do
      case payload["status"] do
        "done" ->
          duration = estimate_duration(payload["reps"])

          log_payload = %{
            "event_id" => message["event_id"] || Elixir.UUID.uuid4(),
            "tenant_id" => message["tenant_id"] || BotArmyCore.Tenant.default_tenant_id(),
            "user_id" => payload["user_id"],
            "payload" => %{
              "workout_type" => payload["exercise"] || "workout",
              "duration_minutes" => duration,
              "equipment" => payload["equipment"],
              "intensity" => "moderate"
            }
          }

          BotArmyFitness.Handlers.WorkoutHandler.handle_log(log_payload)

        "deferred" ->
          defer_count =
            BotArmyRuntime.DeferTracker.record_defer(
              to_string(payload["user_id"]),
              "fitness"
            )

          Logger.info(
            "[Fitness] User #{payload["user_id"]} deferred check-in. Count: #{defer_count}"
          )

        _ ->
          :ok
      end
    end
  end

  defp estimate_duration(reps) when is_binary(reps) do
    cond do
      String.contains?(reps, "3 sets") -> 30
      String.contains?(reps, "4 sets") -> 40
      String.contains?(reps, "5 sets") -> 50
      String.contains?(reps, "2 sets") -> 20
      true -> 30
    end
  end

  defp estimate_duration(_), do: 30

  defp days_until_target(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, target_date} -> Date.diff(target_date, Date.utc_today())
      _ -> nil
    end
  end

  defp days_until_target(_), do: nil
end

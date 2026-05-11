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
      subject: "events.llm.response.parsed",
      type: :subscribe,
      description: "LLM response parsed"
    },
    %{
      subject: "bot_army.fitness.intent.suggest_workout",
      type: :subscribe,
      description: "Intent: suggest workout"
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

        BotArmyRuntime.Registry.register("fitness", @subjects, @version)
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
      BotArmyRuntime.Registry.register("fitness", @subjects, @version)
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

      "llm.response.parsed" ->
        BotArmyFitness.Handlers.WorkoutPlanHandler.handle_llm_response(message)

      _ ->
        Logger.debug("Unknown Fitness event type: #{event}")
    end
  end

  defp handle_goal_progress(nats_msg, message) do
    if nats_msg.reply_to do
      payload = message["payload"] || %{}
      goal_id = payload["goal_id"]

      goal = BotArmyFitness.GoalStore.get(goal_id)

      response =
        case goal do
          nil ->
            %{"error" => "Goal not found"}

          goal_data ->
            workouts_last_30 = count_recent_workouts(goal_id)
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

  defp count_recent_workouts(_goal_id) do
    {:ok, workouts} = BotArmyFitness.WorkoutStore.list()
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

  defp days_until_target(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, target_date} -> Date.diff(target_date, Date.utc_today())
      _ -> nil
    end
  end

  defp days_until_target(_), do: nil
end

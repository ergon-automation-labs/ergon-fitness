defmodule BotArmyFitness.Handlers.CoachChatHandler do
  @moduledoc """
  The coach, asked a question: `fitness.coach.chat`.

  One hop from her question to an answer that is grounded in this gym. The handler gathers the
  three things `BotArmyFitness.CoachChat` needs — the session the rotation owes, her own next
  numbers, and her last training day — builds the message, and asks the LLM bot for a reply.

  ## Why this is not `fitness.chat`

  `fitness.chat` is the persona: it answers in the Resistance Chronicle's voice and is given
  narrative context, not her log. This verb answers as a coach and is given the catalog, the
  method and her log, and its rules refuse exactly what that voice would happily invent — a
  movement this house does not own, a plan chosen for her. Same LLM, different facts and
  different rules, so it is a different subject rather than a mode of the old one.

  ## Why it is spawned by the consumer and not awaited

  Every fitness subscription rides on one consumer process, and the LLM round trip is measured
  in seconds while every other read on this bot is a database hop. Answering in the consumer
  would mean today's session and the movement menu going quiet behind one person's question.
  The consumer therefore spawns this and the mailbox keeps moving; this process owns its own
  reply, and it replies on every path — an answer, a refusal, or the news that the coach could
  not answer — because a question that never gets an answer is the panel waiting forever.

  ## A grounded answer, or an honest refusal

  There is no path here that invents a fact. If the LLM hop fails or answers something that is
  not text, the reply is `:llm_failed` with a sentence of its own, not a made-up session. If the
  log could not be read, the facts say so and the model is told not to describe her log — the
  answer is still an answer about the gym, and the page can draw it.
  """

  require Logger

  alias BotArmyFitness.{Coach, CoachChat, LlmReply, Scheduler, WorkoutSetStore}
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  # Longer than the persona's eight seconds: the grounded message is much bigger — the whole
  # menu, the method and her log — and this is the one read on the panel a person is watching
  # a "thinking" line for rather than blocking a page on.
  @llm_timeout_ms 20_000

  @doc """
  Answer a `fitness.coach.chat` request. Always answers, never raises.

  Returns `:ok` rather than a reply body: this handler is run in its own process and publishes
  its own reply, because the LLM hop may outlive the consumer's dispatch.
  """
  @spec handle_chat(map(), String.t() | nil) :: :ok
  def handle_chat(message, reply_to) when is_binary(reply_to) and reply_to != "" do
    result =
      try do
        %{tenant_id: tenant_id, user_id: user_id} = Tenant.extract_context(message)
        payload = message["payload"] || message
        question = payload["message"] || payload["question"]

        if is_binary(question) and String.trim(question) != "" do
          ask(tenant_id, user_id, question)
        else
          {:error, :missing_message}
        end
      rescue
        e ->
          Logger.warning("The coach chat raised: #{inspect(e)}")
          {:error, {:raised, e}}
      end

    publish(reply_to, result)
    :ok
  end

  def handle_chat(_message, _reply_to), do: :ok

  defp ask(tenant_id, user_id, question) do
    context = context(tenant_id)

    BotArmyLibraryRuntime.NATS.Publisher.request(
      "llm.prompt.submit",
      %{
        "text" => CoachChat.prompt(question, context),
        "request_type" => "chat",
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "timeout_ms" => @llm_timeout_ms
      },
      timeout_ms: @llm_timeout_ms
    )
    |> LlmReply.read()
  end

  # The context is built tolerantly on purpose: a part that could not be read is carried as
  # missing so `CoachChat` can say so in the facts, rather than taking the whole answer down.
  # A question about the MaxPRO should be answerable on a day the log is not.
  #
  # Public only so the tests can prove the tolerance — the read that must not turn a hiccup into
  # "you have kept nothing" is exactly the one worth pinning.
  @doc false
  def context(tenant_id) do
    last = last_session(tenant_id)

    case days_trained() do
      {:ok, days} when is_integer(days) ->
        %{
          today: today(tenant_id, Coach.owed(days), days),
          days_trained: days,
          last: last
        }

      _other ->
        %{today: nil, days_trained: nil, last: last}
    end
  end

  defp today(tenant_id, session, days) when is_map(session) and is_integer(days) do
    case history(tenant_id, session) do
      {:ok, history} -> Coach.plan(session, history)
      {:error, _reason} -> nil
    end
  end

  defp today(_tenant_id, _session, _days), do: nil

  defp days_trained do
    Scheduler.training_days()
  rescue
    e -> {:error, e}
  end

  defp history(tenant_id, session) do
    case set_store().newest_per_exercise(tenant_id, movements_in(session)) do
      {:ok, history} when is_map(history) -> {:ok, history}
      other -> {:error, {:unexpected_store_reply, other}}
    end
  rescue
    e -> {:error, e}
  end

  defp movements_in(session) do
    session["slots"]
    |> Enum.flat_map(& &1["options"])
    |> Enum.uniq()
  end

  # One entry per movement, in the order she last touched them — the same rule
  # `fitness.coach.last` answers with, so the two tell her the same story about the same day.
  # A failed read is `:unreadable` and not `nil`: "she has kept nothing" must not be produced by
  # a database hiccup, and `CoachChat` says the difference out loud.
  defp last_session(tenant_id) do
    case set_store().recent_day(tenant_id) do
      {:ok, nil} ->
        nil

      {:ok, %{"date" => day, "sets" => sets}} when is_binary(day) and is_list(sets) ->
        %{"day" => day, "movements" => movements(sets)}

      {:error, reason} ->
        Logger.warning("The coach chat could not read her log: #{inspect(reason)}")
        :unreadable

      other ->
        Logger.warning("The coach chat could not read her log: #{inspect(other)}")
        :unreadable
    end
  rescue
    e ->
      Logger.warning("The coach chat could not read her log: #{inspect(e)}")
      :unreadable
  end

  # The store's row spelled the way `CoachChat` reads a movement: the movement's value, and
  # the set exactly as it was kept. Nothing is re-derived and nothing she did is dropped.
  defp movements(sets) do
    sets
    |> Enum.uniq_by(& &1["exercise"])
    |> Enum.map(fn set ->
      %{
        "value" => set["exercise"],
        "measure" => set["measure"],
        "amount" => set["amount"],
        "load_kind" => set["load_kind"],
        "load_value" => set["load_value"]
      }
    end)
  end

  defp set_store do
    Application.get_env(:bot_army_fitness, :workout_set_store, WorkoutSetStore)
  end

  defp publish(reply_to, result), do: reply(reply_to, reply_payload(result))

  @doc false
  def reply_payload({:ok, text}), do: Reply.ok(%{"response" => text})

  def reply_payload({:error, :missing_message}),
    do: Reply.error("ask the coach a question", :missing_message)

  def reply_payload({:error, reason}) do
    Logger.warning("The coach could not answer: #{inspect(reason)}")
    Reply.error("the coach could not answer just now", :llm_failed)
  end

  defp reply(reply_to, encoded) do
    case GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} -> Gnat.pub(conn, reply_to, encoded)
      {:error, reason} -> Logger.warning("[coach chat] Failed to reply: #{inspect(reason)}")
    end
  end
end

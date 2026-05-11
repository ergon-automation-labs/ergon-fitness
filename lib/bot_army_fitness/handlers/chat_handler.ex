defmodule BotArmyFitness.Handlers.ChatHandler do
  @moduledoc """
  Handles conversational chat requests to the Fitness Bot persona.

  Receives `fitness.chat` messages, forwards to the LLM bot with the
  Fitness Bot system prompt, and replies via NATS reply_to.
  """

  require Logger

  @llm_request_timeout_ms 8_000

  @doc """
  Handle a chat message request.

  Expects payload with `message` (string). Optional `session_id` for future
  conversation continuity. Replies on `reply_to` with `{"response": "..."}`
  or `{"error": "..."}`.
  """
  def handle_chat(message, reply_to) when is_binary(reply_to) and reply_to != "" do
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)
    payload = message["payload"] || %{}
    user_message = payload["message"] || ""
    session_id = payload["session_id"] || UUID.uuid4()

    if user_message == "" do
      reply(reply_to, %{"error" => "missing_message"})
    else
      response =
        case call_llm(tenant_id, user_id, session_id, user_message) do
          {:ok, text} -> %{"response" => text}
          {:error, reason} -> %{"error" => inspect(reason)}
        end

      reply(reply_to, response)
    end
  end

  def handle_chat(_message, _reply_to), do: :ok

  defp call_llm(tenant_id, user_id, session_id, user_message) do
    prompt = build_prompt(user_message)

    llm_payload = %{
      "text" => prompt,
      "request_type" => "chat",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "session_id" => session_id,
      "timeout_ms" => @llm_request_timeout_ms
    }

    case BotArmyRuntime.NATS.Publisher.request(
           "llm.prompt.submit",
           llm_payload,
           timeout_ms: @llm_request_timeout_ms
         ) do
      {:ok, %{body: body}} when is_binary(body) ->
        decode_llm_response(body)

      {:ok, body} when is_binary(body) ->
        decode_llm_response(body)

      {:ok, decoded} when is_map(decoded) ->
        extract_text(decoded)

      {:error, reason} ->
        Logger.warning("[ChatHandler] LLM request failed: #{inspect(reason)}")
        {:error, reason}

      {:timeout, _} ->
        Logger.warning("[ChatHandler] LLM request timed out")
        {:error, :timeout}
    end
  end

  @doc false
  def build_prompt(user_message) do
    system = BotArmyFitness.Personality.system_prompt()

    """
    #{system}

    User: #{user_message}

    ▲
    """
  end

  @doc false
  def decode_llm_response(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> extract_text(decoded)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def extract_text(%{"completion" => text}) when is_binary(text) and text != "", do: {:ok, text}
  def extract_text(%{"response" => text}) when is_binary(text) and text != "", do: {:ok, text}

  def extract_text(%{"data" => %{"text" => text}}) when is_binary(text) and text != "",
    do: {:ok, text}

  def extract_text(other) do
    Logger.debug("[ChatHandler] Unexpected LLM response shape: #{inspect(other)}")
    {:error, :invalid_response}
  end

  defp reply(reply_to, payload) do
    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      Gnat.pub(conn, reply_to, Jason.encode!(payload))
    else
      {:error, reason} ->
        Logger.warning("[ChatHandler] Failed to publish reply: #{inspect(reason)}")
    end
  end
end

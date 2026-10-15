defmodule BotArmyFitness.LlmReply do
  @moduledoc """
  Reading the LLM bot's answer, in the one place.

  Two things in this bot talk to a language model — the persona at `fitness.chat` and the
  grounded coach at `fitness.coach.chat`. Both send a prompt on `llm.prompt.submit` and both
  have to read whatever comes back, and "whatever comes back" is not one shape: the reply hop
  may hand back a raw body or an already-decoded map, and the model's text may sit under
  `completion`, `response`, or `data.text` depending on which provider answered. Every one of
  those is a fact about the hop and not about fitness, so it lives here once rather than in
  each handler, where the two copies would drift and one of them would be the one that is
  wrong.

  Nothing here raises and nothing here guesses. A reply this module cannot read is
  `{:error, :invalid_response}`; a hop that failed is its own error; the caller decides what
  to say to her.
  """

  require Logger

  @doc """
  The text of an already-decoded LLM reply, or `{:error, :invalid_response}`.

  An empty string is not text: a model that answered nothing has not answered.
  """
  @spec text(term()) :: {:ok, String.t()} | {:error, :invalid_response}
  def text(%{"completion" => text}) when is_binary(text) and text != "", do: {:ok, text}
  def text(%{"response" => text}) when is_binary(text) and text != "", do: {:ok, text}

  def text(%{"data" => %{"text" => text}}) when is_binary(text) and text != "",
    do: {:ok, text}

  def text(other) do
    Logger.debug("[llm] Unexpected LLM reply shape: #{inspect(other)}")
    {:error, :invalid_response}
  end

  @doc "Decode a raw LLM reply body and read its text."
  @spec decode(binary()) :: {:ok, String.t()} | {:error, term()}
  def decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> text(decoded)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Read an LLM reply in any of the shapes the reply hop may carry it.

  `Publisher.request/3` answers `{:ok, %{body: body}}`, `{:ok, body}`, or `{:ok, decoded}`;
  it answers `{:error, reason}` when the hop itself failed, and `{:timeout, _}` when the
  caller stopped waiting. All five are one call here so a handler reads a reply with one
  line and does not have to know the hop's vocabulary.
  """
  @spec read(term()) :: {:ok, String.t()} | {:error, term()}
  def read({:ok, %{body: body}}) when is_binary(body), do: decode(body)
  def read({:ok, body}) when is_binary(body), do: decode(body)
  def read({:ok, decoded}) when is_map(decoded), do: text(decoded)
  def read({:error, reason}), do: {:error, reason}
  def read({:timeout, _timeout}), do: {:error, :timeout}
  def read(other), do: {:error, {:unexpected_llm_reply, other}}
end

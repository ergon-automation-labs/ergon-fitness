defmodule BotArmyFitness.TavernMemory do
  @moduledoc """
  In-memory tavern continuity for the fitness bot.

  Remembers recent tavern messages, tracks mood based on observed events,
  and allows contextual callbacks to earlier chatter.
  """

  use GenServer

  @max_memory 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def record_gossip(source, text) do
    GenServer.cast(__MODULE__, {:record, source, text})
  end

  def recent_messages do
    GenServer.call(__MODULE__, :recent)
  end

  def current_mood do
    GenServer.call(__MODULE__, :mood)
  end

  def callback_earlier do
    GenServer.call(__MODULE__, :callback)
  end

  @impl true
  def init(_opts) do
    {:ok, %{messages: [], mood_score: 0}}
  end

  @impl true
  def handle_cast({:record, source, text}, state) do
    entry = %{source: source, text: text, at: DateTime.utc_now()}
    messages = Enum.take([entry | state.messages], @max_memory)
    mood = update_mood(state.mood_score, text)
    {:noreply, %{state | messages: messages, mood_score: mood}}
  end

  @impl true
  def handle_call(:recent, _from, state) do
    {:reply, state.messages, state}
  end

  @impl true
  def handle_call(:mood, _from, state) do
    {:reply, state.mood_score, state}
  end

  @impl true
  def handle_call(:callback, _from, state) do
    reply =
      case state.messages do
        [] -> nil
        [%{source: s, text: t} | _] -> "Earlier I noticed #{s} said: #{String.slice(t, 0..60)}..."
      end

    {:reply, reply, state}
  end

  defp update_mood(current, text) do
    down = String.downcase(text)

    delta =
      cond do
        String.contains?(down, "failed") or String.contains?(down, "error") or
            String.contains?(down, "broke") ->
          -2

        String.contains?(down, "completed") or String.contains?(down, "done") or
            String.contains?(down, "success") ->
          +2

        String.contains?(down, "workout") or String.contains?(down, "exercise") ->
          +1

        String.contains?(down, "streak") and String.contains?(down, "no") ->
          -1

        true ->
          0
      end

    clamp(current + delta, -5, 5)
  end

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _, _), do: v
end

defmodule BotArmyFitness.Handlers.GearSetupHandler do
  @moduledoc """
  Move the cable machine: `fitness.gear.setup`.

  The one write behind the plan's *ordering*. `BotArmyFitness.Gear` decides what a position
  costs — which movements the room can do as it stands — and this verb records which
  position the room is in. Raising the cable to the wall is one press on the card; putting
  it back on the floor is the same verb with the other word.

  ## The words are the catalog's, and the refusal says so

  `"floor"` and `"wall"` are `Gear.positions/0`, the same list the plan reads. Anything
  else is refused (`:bad_position`) with a sentence that names both, because a caller that
  sent `"attached"` needs to be told the vocabulary rather than guess it.

  ## Idempotent, because a room has a state and not a history

  Setting the position it is already in answers `{:ok, position}` — the same fact stated
  again is not an error. That is what makes a card safe to press twice: the row is
  overwritten in place, so two presses cannot produce two rooms.

  ## A write that fails is a failure, not a silent plan

  A database that refuses the write answers `:persist_failed`. The caller must not treat
  that as "done": the plan it reads next would still be built for the old room, and the
  card would show a session for equipment she just moved.
  """

  require Logger

  alias BotArmyFitness.{Gear, GearSetupStore}
  alias BotArmyLibraryCore.Tenant
  alias BotArmyLibraryRuntime.NATS.Reply

  @doc """
  Handle a `fitness.gear.setup` request. Always answers, never raises.

  Returns an already-encoded `Reply` binary, so the consumer's clause is one line.
  """
  def handle_setup(message) do
    %{tenant_id: tenant_id} = Tenant.extract_context(message)
    payload = message["payload"] || message

    case position(payload) do
      {:ok, position} -> write(tenant_id, position)
      {:error, :bad_position} -> Reply.error(refusal_sentence(), :bad_position)
    end
  rescue
    e ->
      Logger.warning("The gear setup write raised: #{inspect(e)}")
      Reply.error("the room's setup could not be recorded", :persist_failed)
  end

  @doc "The sentence a refused position answers with — both words, in the catalog's own spelling."
  @spec refusal_sentence() :: String.t()
  def refusal_sentence do
    "the cable machine is either on the floor or at the wall"
  end

  # Two spellings are accepted for the same field because the card and the plan name it
  # differently ("maxpro" is the piece, "position" is what she is changing about it), and a
  # caller should not have to know which one this door prefers.
  defp position(payload) do
    value = payload["maxpro"] || payload["position"]

    if value in Gear.positions(), do: {:ok, value}, else: {:error, :bad_position}
  end

  defp write(tenant_id, position) do
    case store().put(tenant_id, position) do
      {:ok, written} ->
        Reply.ok(%{"gear" => %{"maxpro" => written}})

      {:error, :bad_position} ->
        Reply.error(refusal_sentence(), :bad_position)

      {:error, reason} ->
        Logger.warning("Failed to record the room's setup: #{inspect(reason)}")

        Reply.error("the room's setup could not be recorded", :persist_failed)
    end
  end

  defp store do
    Application.get_env(:bot_army_fitness, :gear_setup_store, GearSetupStore)
  end
end

defmodule BotArmyFitness.HouseholdDay do
  @moduledoc """
  The day this bot files a set under, and the day "today" means everywhere in it.

  A bot that stamps its rows with `Date.utc_today/0` is a bot whose day changes at 18:00
  for a house in Denver: a set kept at seven in the evening is filed as *tomorrow*, and a
  card that says "today's session" turns somewhere in the middle of her evening instead of
  while she sleeps. The log and the method have to agree about which day a set landed on —
  `BotArmyFitness.WorkoutSetStore` says so in as many words — and the day a person is
  living in is the house's day, not Greenwich's.

  So there is one answer to "what day is it", it is here, and every part of this bot that
  files a day or compares one asks this module. It reads the host's own zone, which for
  this household is the household's zone: both instances run on this house's machines, and
  the zone travels in the deployment beside every other environment fact.

  ## Why not a time zone database

  There is no IANA database anywhere in this fleet, and adding one for a subtraction is a
  bad trade: a new dependency plus a compile-time download to learn an offset that the
  runtime already knows. `:calendar.local_time/0` asks the host the same question — the
  host the bot is running on is the host whose clock the household lives by — and the
  module carries no state to keep in step with it. `offset_hours/0` exists so a host in
  the wrong zone can be *seen* to be in the wrong zone rather than suspected: it is logged
  at boot.

  ## The seam, and why it is an application environment key

  Tests must not change meaning at midnight, and neither must a suite run on a machine in
  another zone. Set `:household_today` to a zero-arity function in the application
  environment and every caller of `today/0` answers the pinned day:

      Application.put_env(:bot_army_fitness, :household_today, fn -> ~D[2026-01-01] end)

  Nothing else reads that key, so a test that pins it pins this one fact and no other.
  """

  @doc """
  Today, in the house's own day.

  Every day this bot writes down, and every "days since" it counts, is counted from
  here. `Date.utc_today/0` is not the same question and must not be used to answer this
  one.
  """
  @spec today() :: Date.t()
  def today, do: clock().()

  @doc """
  How many hours this host's clock stands from UTC right now.

  Not used to compute a day — `today/0` is the host's own answer and is not derived from
  an offset. It exists to be logged and read, so that a host whose zone is not the
  household's is visible in the log instead of hiding as a wrong answer that only shows
  up after six in the evening.
  """
  @spec offset_hours() :: integer()
  def offset_hours do
    local = :calendar.datetime_to_gregorian_seconds(:calendar.local_time())
    utc = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())

    div(local - utc, 3_600)
  end

  defp clock, do: Application.get_env(:bot_army_fitness, :household_today, &local_today/0)

  defp local_today do
    {date, _time} = :calendar.local_time()
    Date.from_erl!(date)
  end
end

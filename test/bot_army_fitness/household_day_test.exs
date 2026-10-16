defmodule BotArmyFitness.HouseholdDayTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.HouseholdDay

  describe "today/0" do
    test "answers the day the seam is pinned to" do
      pin(~D[2026-12-31])

      assert HouseholdDay.today() == ~D[2026-12-31]
    end

    test "with nothing pinned it answers the host's own day" do
      # Deliberately not compared to `Date.utc_today/0`: an assertion that the two agree would
      # pass all day and fail between six in the evening and midnight in this house — exactly
      # the bug this module exists to fix, written down as a test that would go red for it.
      # What can be said without reading a clock is that it is a day, and that no real zone
      # stands more than a day from UTC.
      day = HouseholdDay.today()

      assert %Date{} = day
      assert abs(Date.diff(day, Date.utc_today())) <= 1
    end
  end

  describe "offset_hours/0" do
    test "answers the whole-hour offset this host's clock stands from UTC" do
      offset = HouseholdDay.offset_hours()

      assert is_integer(offset)
      assert offset >= -14 and offset <= 14
    end
  end

  describe "one day convention in this bot" do
    # A lint, not a behaviour proof, and it says so: the failure it guards against is a line
    # someone adds later, and no test of today's behaviour would notice. Two conventions in one
    # bot is where the reported bug came from — the set log filed by one day and the coach
    # reading another — so the rule is that `lib/` asks `HouseholdDay` and never the UTC clock.
    test "no file in lib/ reads the UTC day as this bot's day" do
      offenders =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.filter(fn path ->
          path
          |> File.read!()
          |> String.split("\n")
          |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
          |> Enum.any?(&String.contains?(&1, "Date.utc_today()"))
        end)

      assert offenders == [],
             """
             These files answer "what day is it" with `Date.utc_today/0`:

             #{Enum.map_join(offenders, "\n", &"  #{&1}")}

             The house's day is `BotArmyFitness.HouseholdDay.today/0`, and it is one answer
             for the whole bot: a set filed in the evening belongs to the day she lived, not
             to tomorrow. Nothing is exempt — not even `household_day.ex`, which explains the
             rule without asking the UTC clock a question of its own.
             """
    end
  end

  defp pin(day) do
    Application.put_env(:bot_army_fitness, :household_today, fn -> day end)
    on_exit(fn -> Application.delete_env(:bot_army_fitness, :household_today) end)
  end
end

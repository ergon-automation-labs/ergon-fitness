defmodule BotArmyFitnessTest do
  use ExUnit.Case
  @moduletag :core
  doctest BotArmyFitness

  test "version" do
    assert BotArmyFitness.version() == "0.1.0"
  end
end

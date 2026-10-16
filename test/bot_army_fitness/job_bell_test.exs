defmodule BotArmyFitness.JobBellTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyFitness.JobBell

  # The registry is started by the application (it is the local half of the llm bot's bell), so
  # these tests use the real one and clean up after themselves.

  test "ringing wakes every process waiting on that job" do
    JobBell.watch("job-a")
    JobBell.ring("job-a")
    assert_receive {:job_bell, "job-a"}
  after
    JobBell.unwatch("job-a")
  end

  test "a waiter stops hearing once it stops waiting" do
    JobBell.watch("job-b")
    JobBell.unwatch("job-b")
    JobBell.ring("job-b")
    refute_receive {:job_bell, "job-b"}, 20
  end

  test "a ring for a job nobody is waiting on is harmless" do
    assert JobBell.ring("job-nobody") == :ok
  end

  test "a ring for one job does not wake the waiter of another" do
    JobBell.watch("job-c")
    JobBell.ring("job-d")
    refute_receive {:job_bell, "job-c"}, 20
  after
    JobBell.unwatch("job-c")
  end
end

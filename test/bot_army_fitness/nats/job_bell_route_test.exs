defmodule BotArmyFitness.NATS.JobBellRouteTest do
  use ExUnit.Case
  @moduletag :nats

  alias BotArmyFitness.{JobBell, NATS.Consumer}

  # The llm bot's completion event carries a job id and nothing else. The consumer's only job on
  # it is to ring the local bell; the waiting process reads the words from the llm bot's store.
  # These tests prove that route without a broker: `route_message/2` is the same function the
  # GenServer calls for a decoded message.

  test "a completion event rings the bell for that job" do
    JobBell.watch("job-route-1")

    Consumer.route_message(
      %{"event" => "llm.job.completed", "payload" => %{"job_id" => "job-route-1"}},
      %{}
    )

    assert_receive {:job_bell, "job-route-1"}
  after
    JobBell.unwatch("job-route-1")
  end

  test "a completion event for another job does not ring mine" do
    JobBell.watch("job-route-2")

    Consumer.route_message(
      %{"event" => "llm.job.completed", "payload" => %{"job_id" => "job-route-other"}},
      %{}
    )

    refute_receive {:job_bell, "job-route-2"}, 20
  after
    JobBell.unwatch("job-route-2")
  end

  test "a completion event with no job id does not crash the consumer" do
    assert Consumer.route_message(%{"event" => "llm.job.completed", "payload" => %{}}, %{}) == :ok
  end

  test "the bell subject is subscribed" do
    assert Enum.any?(Consumer.subjects(), fn %{subject: subject} ->
             subject == "events.llm.job.completed"
           end)
  end
end

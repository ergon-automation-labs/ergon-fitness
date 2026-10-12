defmodule BotArmyFitness.NATS.ConsumerQueueGroupTest do
  use ExUnit.Case
  @moduletag :nats

  alias BotArmyFitness.NATS.Consumer

  describe "subscribe_all/1 — the queue group that stopped the double processing" do
    test "subscribes every advertised subject on the shared group" do
      subscriptions = collect_subscriptions()

      assert length(subscriptions) == length(Consumer.subjects())

      assert subscriptions |> Enum.map(fn {subject, _opts} -> subject end) |> Enum.sort() ==
               Consumer.subjects() |> Enum.map(& &1.subject) |> Enum.sort()
    end

    test "no subscription is a bare (queue-group-less) subscribe" do
      # Both air and mini run this bot. Without a queue group each node received
      # every message, so every workout log wrote twice.
      bare =
        subscriptions()
        |> Enum.reject(fn {_subject, opts} -> opts[:queue_group] == Consumer.queue_group() end)

      assert bare == []
    end

    test "the group is shared by both nodes, not per-node" do
      assert Consumer.queue_group() == "fitness_bot"
      refute Consumer.queue_group() =~ "air"
      refute Consumer.queue_group() =~ "mini"
    end

    test "request/reply subjects are grouped too, so one node answers" do
      request_subjects =
        Consumer.subjects()
        |> Enum.filter(&(&1.type == :request_reply))
        |> Enum.map(& &1.subject)

      assert "fitness.workout.list" in request_subjects
      assert "fitness.workout.log" in request_subjects

      grouped =
        Map.new(subscriptions(), fn {subject, opts} -> {subject, opts[:queue_group]} end)

      for subject <- request_subjects do
        assert grouped[subject] == Consumer.queue_group()
      end
    end
  end

  defp subscriptions do
    collect_subscriptions()
  end

  defp collect_subscriptions do
    parent = self()

    Consumer.subscribe_all(fn subject, opts -> send(parent, {:subscribed, subject, opts}) end)

    drain([])
  end

  defp drain(acc) do
    receive do
      {:subscribed, subject, opts} -> drain([{subject, opts} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end

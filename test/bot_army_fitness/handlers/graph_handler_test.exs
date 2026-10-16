defmodule BotArmyFitness.Handlers.GraphHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyFitness.Graphs
  alias BotArmyFitness.Handlers.GraphHandler
  alias BotArmyFitness.HouseholdDay

  setup :set_mox_global

  @tenant "00000000-0000-0000-0000-000000000001"

  # There is no Mox mock for the cardio store, and a behaviour plus a mock for the one
  # read the graphs need would be more machinery than the seam the handler actually has.
  # This stands in for the store through that seam and answers with whatever the test put
  # in the process dictionary, which is empty for every test that does not care.
  defmodule CardioStub do
    @moduledoc false
    def list_recent(tenant, days) do
      {:ok, Process.get({:cardio_sessions, tenant, days}) || []}
    end
  end

  setup do
    previous = Application.get_env(:bot_army_fitness, :cardio_session_store)
    Application.put_env(:bot_army_fitness, :cardio_session_store, CardioStub)
    on_exit(fn -> Application.put_env(:bot_army_fitness, :cardio_session_store, previous) end)

    stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant -> {:ok, []} end)
    stub(BotArmyFitness.WorkoutSetStoreMock, :since, fn _tenant, _since -> {:ok, []} end)
    :ok
  end

  describe "handle_graphs/1" do
    test "answers the whole menu, each series with its points" do
      reply = decode(GraphHandler.handle_graphs(request()))

      assert reply["ok"] == true
      assert reply["data"]["count"] == length(reply["data"]["graphs"])
      assert reply["data"]["window_days"] == Graphs.window_days()

      assert Enum.map(reply["data"]["graphs"], & &1["id"]) ==
               Enum.map(Graphs.build(%{}, HouseholdDay.today()), & &1["id"])

      for graph <- reply["data"]["graphs"] do
        assert is_binary(graph["title"])
        assert is_binary(graph["note"])
        assert graph["kind"] in ["bars", "line"]
        assert is_list(graph["points"])
      end
    end

    test "reads the sets from the window the labels describe, not from the whole log" do
      today = HouseholdDay.today()

      stub(BotArmyFitness.WorkoutSetStoreMock, :since, fn @tenant, since ->
        send(self(), {:since, since})
        {:ok, []}
      end)

      _ = GraphHandler.handle_graphs(request())

      assert_received {:since, since}
      assert since == Date.add(today, -Graphs.window_days())
    end

    test "puts the numbers the stores returned into the weeks they belong to" do
      today = HouseholdDay.today()

      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn @tenant -> {:ok, [today]} end)

      stub(BotArmyFitness.WorkoutSetStoreMock, :since, fn @tenant, _since ->
        {:ok, [set_row(Date.to_string(today))]}
      end)

      reply = decode(GraphHandler.handle_graphs(request()))
      sessions = series(reply, "fitness.sessions.week")

      assert List.last(sessions["points"]) ==
               %{
                 "label" =>
                   Calendar.strftime(
                     Graphs.week_buckets(today, 1) |> hd() |> Map.fetch!(:start),
                     "%b %-d"
                   ),
                 "value" => 1
               }
    end

    test "sums the cardio sessions the store returned into their own weeks" do
      today = HouseholdDay.today()
      Process.put({:cardio_sessions, @tenant, Graphs.window_days()}, [cardio_row(today)])

      reply = decode(GraphHandler.handle_graphs(request()))

      assert List.last(series(reply, "fitness.cardio.miles.week")["points"])["value"] == 2.5
      assert List.last(series(reply, "fitness.cardio.minutes.week")["points"])["value"] == 30
    end

    test "a store that cannot answer is a refusal, not a shorter menu" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :distinct_days, fn _tenant ->
        raise "could not lookup Ecto repo"
      end)

      reply = decode(GraphHandler.handle_graphs(request()))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
      refute Map.has_key?(reply, "data")
    end

    test "a store that answers with something unexpected is a refusal too" do
      stub(BotArmyFitness.WorkoutSetStoreMock, :since, fn _tenant, _since -> :no_reply end)

      reply = decode(GraphHandler.handle_graphs(request()))

      assert reply["ok"] == false
      assert reply["code"] == "read_failed"
    end
  end

  describe "parity with the published schema" do
    test "the reply's only refusal is the one the handler utters" do
      path =
        Path.expand("../../../../../schemas/bot_army_schemas_fitness/schemas", __DIR__)
        |> Path.join("fitness.graph.series.reply.json")

      [_ok, refused] = path |> File.read!() |> Jason.decode!() |> Map.fetch!("oneOf")

      assert refused["properties"]["code"]["enum"] == ["read_failed"]
    end
  end

  defp request do
    %{
      "event" => "fitness.graph.series",
      "tenant_id" => @tenant,
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "payload" => %{}
    }
  end

  defp series(reply, id), do: Enum.find(reply["data"]["graphs"], &(&1["id"] == id))

  defp set_row(date) do
    %{
      "id" => UUID.uuid4(),
      "exercise" => "cable_row",
      "measure" => "reps",
      "amount" => 10,
      "load_kind" => "level",
      "load_value" => 18,
      "date" => date
    }
  end

  defp cardio_row(date) do
    %{
      "session_date" => Date.to_string(date),
      "distance_miles" => 2.5,
      "duration_minutes" => 30
    }
  end

  defp decode(encoded) when is_binary(encoded), do: Jason.decode!(encoded)
end

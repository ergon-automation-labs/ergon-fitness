defmodule BotArmyFitness.Handlers.ChatHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  describe "build_prompt/1" do
    test "includes system prompt and user message" do
      prompt = BotArmyFitness.Handlers.ChatHandler.build_prompt("how was my week?")

      assert prompt =~ "Fitness Bot for Ergon Labs"
      assert prompt =~ "how was my week?"
      assert prompt =~ "▲"
    end
  end

  describe "extract_text/1" do
    test "extracts completion field" do
      assert {:ok, "hello"} =
               BotArmyFitness.Handlers.ChatHandler.extract_text(%{"completion" => "hello"})
    end

    test "extracts response field" do
      assert {:ok, "hi there"} =
               BotArmyFitness.Handlers.ChatHandler.extract_text(%{"response" => "hi there"})
    end

    test "extracts nested data.text field" do
      assert {:ok, "nested"} =
               BotArmyFitness.Handlers.ChatHandler.extract_text(%{"data" => %{"text" => "nested"}})
    end

    test "returns error for empty completion" do
      assert {:error, :invalid_response} =
               BotArmyFitness.Handlers.ChatHandler.extract_text(%{"completion" => ""})
    end

    test "returns error for unexpected shape" do
      assert {:error, :invalid_response} =
               BotArmyFitness.Handlers.ChatHandler.extract_text(%{"foo" => "bar"})
    end
  end

  describe "decode_llm_response/1" do
    test "decodes JSON and extracts text" do
      body = Jason.encode!(%{"completion" => "workout done"})

      assert {:ok, "workout done"} =
               BotArmyFitness.Handlers.ChatHandler.decode_llm_response(body)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = BotArmyFitness.Handlers.ChatHandler.decode_llm_response("not json")
    end
  end

  describe "handle_chat/2" do
    test "returns :ok when reply_to is missing" do
      assert :ok =
               BotArmyFitness.Handlers.ChatHandler.handle_chat(%{"payload" => %{}}, nil)
    end

    test "returns :ok when reply_to is empty string" do
      assert :ok =
               BotArmyFitness.Handlers.ChatHandler.handle_chat(%{"payload" => %{}}, "")
    end
  end
end

# frozen_string_literal: true

require_relative "../config/environment"

def test_llm
  client = Services::Ai::OpenaiClient.instance
  model = ENV["OLLAMA_MODEL"] || "qwen3-vl:latest"
  puts "Testing Ollama connection with model: #{model}..."

  prompt = "Say hello and give a very brief trading tip."

  # Use generate (the direct method we added)
  response = client.generate(prompt: prompt, model: model)

  if response
    puts "\n--- RESPONSE ---\n"
    puts response
    puts "\n----------------\n"
  else
    puts "\n❌ FAILED: No response received. Check if Ollama is running and has the model pulled."
    puts "Try: ollama pull #{model}"
  end
rescue StandardError => e
  puts "\n❌ ERROR: #{e.class} - #{e.message}"
end

test_llm

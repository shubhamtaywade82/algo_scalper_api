# frozen_string_literal: true

# Configure the ollama-client gem for cloud or local Ollama.
#
# Environment variables (same as ollama_agent):
#   OLLAMA_BASE_URL  — Ollama endpoint, e.g. https://ollama.com (cloud) or http://localhost:11434 (local)
#   OLLAMA_API_KEY   — Required for Ollama Cloud; omit for local instances
#   OLLAMA_MODEL     — Default model name (e.g. "llama3.2:3b" or a cloud model slug)
#   OLLAMA_TIMEOUT   — Request timeout in seconds (default: 30)
#
require 'ollama_client'

OllamaClient.configure do |config|
  url = ENV.fetch('OLLAMA_BASE_URL', nil) || ENV.fetch('OLLAMA_HOST_URL', nil)
  config.base_url = url if url.present?

  key = ENV.fetch('OLLAMA_API_KEY', nil)
  config.api_key = key if key.present?

  model = ENV.fetch('OLLAMA_MODEL', nil)
  config.model = model if model.present?

  timeout = ENV.fetch('OLLAMA_TIMEOUT', nil)
  config.timeout = timeout.to_i if timeout.present?
end

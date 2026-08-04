# frozen_string_literal: true

# Configure the ollama-client gem defaults. Runtime target (local vs cloud) is chosen from
# +ai.ollama_use_cloud+ in AlgoConfig (dashboard Settings → AI); see Services::Ai::OllamaClient.
#
# Environment variables (same as ollama_agent):
#   OLLAMA_LOCAL_URL — Optional; local daemon when ollama_use_cloud is false
#   OLLAMA_CLOUD_URL — Optional; cloud API when ollama_use_cloud is true
#   OLLAMA_BASE_URL  — Fallback URL for both modes if the specific URL above is unset
#   OLLAMA_HOST_URL  — Legacy local/LAN URL (local mode)
#   OLLAMA_API_KEY   — Required when ollama_use_cloud is true (Ollama Cloud)
#   OLLAMA_MODEL     — Default model name (e.g. "qwen3.5:4b" or a cloud model slug)
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

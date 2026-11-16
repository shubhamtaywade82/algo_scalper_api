# frozen_string_literal: true

# Single source of truth for which Ollama model every AI path uses: RubyLLM agents,
# Services::Ai::OllamaClient callers and the MCP bridge all read it from here.
#
# Only Ollama is wired. RubyLLM 2.x models Ollama Cloud as its own provider
# (:ollama_cloud, separate credentials) rather than an Ollama base-URL variant,
# so the cloud/local decision picks the provider. Both providers accept any
# model id without a registry entry (Ollama is local; Ollama Cloud declares
# assume_models_exist?), so no models need to be registered at boot.
#
# Env:
#   OLLAMA_BASE_URL  local default http://localhost:11434; https://ollama.com selects Ollama Cloud
#   OLLAMA_API_KEY   bearer token (required for Ollama Cloud)
#   OLLAMA_MODEL           default model (default llama3.2:3b locally, minimax-m2.5 on cloud)
#   OLLAMA_ANALYSIS_MODEL  heavier model for analysis/report work (defaults to OLLAMA_MODEL)
#   OLLAMA_TIMEOUT   request timeout seconds for agent calls (default 60)
module LLMSettings
  LOCAL_DEFAULT_BASE = 'http://localhost:11434'
  CLOUD_HOST = 'https://ollama.com'
  LOCAL_DEFAULT_MODEL = 'llama3.2:3b'
  CLOUD_DEFAULT_MODEL = 'minimax-m2.5'

  module_function

  def raw_base_url
    ENV['OLLAMA_BASE_URL'].presence || LOCAL_DEFAULT_BASE
  end

  def cloud?
    raw_base_url.start_with?(CLOUD_HOST)
  end

  def provider
    cloud? ? :ollama_cloud : :ollama
  end

  # RubyLLM's Chat Completions client posts to "#{api_base}/chat/completions",
  # so the base must end in /v1 for both local Ollama and Ollama Cloud.
  def api_base
    base = raw_base_url.chomp('/')
    base.end_with?('/v1') ? base : "#{base}/v1"
  end

  def api_key
    ENV['OLLAMA_API_KEY'].presence
  end

  def default_model
    configured = ENV['OLLAMA_MODEL'].presence
    return configured if configured && !(cloud? && configured == LOCAL_DEFAULT_MODEL)

    cloud? ? CLOUD_DEFAULT_MODEL : LOCAL_DEFAULT_MODEL
  end

  # Market Brief, AI snapshot, technical-analysis agent, calibration and other
  # analysis/report calls; quick interactive paths (MCP assistant, agents) use default_model.
  def analysis_model
    ENV['OLLAMA_ANALYSIS_MODEL'].presence || default_model
  end

  def request_timeout
    Integer(ENV.fetch('OLLAMA_TIMEOUT', '60'))
  rescue ArgumentError
    60
  end
end

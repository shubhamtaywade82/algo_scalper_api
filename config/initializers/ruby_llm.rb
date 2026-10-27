# frozen_string_literal: true

# RubyLLM 2.x configuration (https://rubyllm.com). Only Ollama is wired; see
# LLMSettings for provider/model resolution. Applied in to_prepare so the
# autoloaded LLMSettings is available and code reloads pick up env changes.
Rails.application.config.to_prepare do
  RubyLLM.configure do |config|
    if LLMSettings.cloud?
      # Ollama Cloud is a separate provider in 2.x with its own credentials.
      config.ollama_cloud_api_base = LLMSettings.api_base
      config.ollama_cloud_api_key = LLMSettings.api_key
    else
      config.ollama_api_base = LLMSettings.api_base
      config.ollama_api_key = LLMSettings.api_key # optional bearer for a secured local/proxied Ollama
    end

    config.default_model = LLMSettings.default_model
    config.request_timeout = LLMSettings.request_timeout
    # Transient failures (timeouts, 429/5xx) are retried by RubyLLM's Faraday retry middleware.
    config.max_retries = 3
    config.retry_backoff_factor = 2
    config.logger = Rails.logger
  end
end

# Eager-load agent/tool classes at boot. With config.eager_load = false (dev),
# Solid Queue's multi-threaded worker races on the first Zeitwerk autoload of a
# bare `MarketAnalystAgent`-style constant, raising a spurious
# "uninitialized constant" — seen repeatedly in the trading log.
Rails.application.config.after_initialize do
  unless Rails.application.config.eager_load
    Rails.autoloaders.main.eager_load_dir(Rails.root.join('app/agents'))
    Rails.autoloaders.main.eager_load_dir(Rails.root.join('app/tools'))
  end
end

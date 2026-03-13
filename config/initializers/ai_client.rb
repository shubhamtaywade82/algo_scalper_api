# frozen_string_literal: true

# Initialize AI client on application startup (skipped for db/assets rake tasks to avoid blocking on Ollama).
Rails.application.config.after_initialize do
  if defined?(Rake) && Rake.application.respond_to?(:top_level_tasks)
    db_or_assets = Rake.application.top_level_tasks.any? { |t| t.start_with?('db:', 'assets:') }
    next if db_or_assets
  end

  begin
    # Access the class to trigger autoloading
    client_class = Services::Ai::OpenaiClient
    if client_class.instance.enabled?
      Rails.logger.info("[AI] OpenAI client initialized with provider: #{client_class.instance.provider}")
    else
      Rails.logger.info('[AI] OpenAI client disabled or not configured')
    end
  rescue NameError, LoadError => e
    # Module not available or not loaded yet - this is OK if AI is disabled
    Rails.logger.debug("[AI] AI client not available: #{e.message}") if Rails.env.development?
  end
end

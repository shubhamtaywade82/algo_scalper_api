# frozen_string_literal: true

# Woods configuration
# Full reference: https://github.com/lost-in-the/woods/blob/main/docs/CONFIGURATION_REFERENCE.md
#
# Quick-start presets (uncomment one instead of the full block below):
#   Woods.configure_with_preset(:local)       # in-memory + Ollama, no external services
#   Woods.configure_with_preset(:postgresql)  # pgvector + OpenAI (PostgreSQL required)
#   Woods.configure_with_preset(:production)  # Qdrant + OpenAI (production-scale)
#
# Presets accept a block for overrides:
#   Woods.configure_with_preset(:local) { |c| c.max_context_tokens = 16_000 }

if defined?(Woods)
Woods.configure do |config|
  config.output_dir = Rails.root.join('tmp/woods')

  config.embedding_provider = :ollama
  config.embedding_options = {
    model: 'nomic-embed-text',
    host: ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434')
  }

  config.vector_store = :in_memory
  config.metadata_store = :in_memory
end
end

# frozen_string_literal: true

# Boot-time validation of config/investing.yml (TDD §5.2).
# Fail-loud: a malformed investing config aborts the process rather than
# silently degrading risk constraints.
Rails.application.config.to_prepare do
  Investing::Config.load!
  Rails.logger.info("[Investing] config loaded: #{Investing::Config.fetch.mandates.keys.join(', ')}")
end

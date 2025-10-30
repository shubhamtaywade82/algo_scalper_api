# frozen_string_literal: true

# Auto-load paper trading console helpers in Rails console
# Usage in console: paper_wallet, paper_positions, paper_status, paper_position('security_id')
Rails.application.config.to_prepare do
  if defined?(Rails::Console) || defined?(IRB)
    require_relative '../../lib/paper_trading_helpers'

    # Make helpers available in console context
    if Rails.env.development? || Rails.env.test?
      Rails.application.console do
        include PaperTradingHelpers
      end
    end
  end
rescue LoadError
  # Silently fail if file doesn't exist
end


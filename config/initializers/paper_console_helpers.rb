# frozen_string_literal: true

# Auto-load paper trading console helpers in Rails console
# Usage in console: paper_wallet, paper_positions, paper_status, paper_position('security_id')
Rails.application.console do
  require_relative '../../lib/paper_trading_helpers'
  extend PaperTradingHelpers
rescue LoadError
  # Silently fail if file doesn't exist
end


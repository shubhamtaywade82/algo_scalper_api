# frozen_string_literal: true

# Wire the option-chain adapter once at boot.
# Always use DhanAdapter for market data (expiry lists, chain data) — this is read-only and
# needed even in paper mode to select which options to analyse.
# Order execution paper mode is handled separately by Orders::GatewayPaper.
Rails.application.config.after_initialize do
  Instrument.option_chain_adapter = Adapters::OptionChain::DhanAdapter.new
end

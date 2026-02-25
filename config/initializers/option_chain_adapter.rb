# frozen_string_literal: true

# Wire the option-chain adapter once at boot.
# - Paper mode: no broker option-chain calls.
# - Live mode: use DhanHQ adapter.
Rails.application.config.after_initialize do
  paper_mode = begin
    AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
  rescue StandardError
    false
  end

  adapter = if paper_mode
              Adapters::OptionChain::NullAdapter.new
            else
              Adapters::OptionChain::DhanAdapter.new
            end

  Instrument.option_chain_adapter = adapter
end

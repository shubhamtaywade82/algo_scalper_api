# frozen_string_literal: true

# SMC Console Example - Fetch candles for NIFTY and SENSEX
# Usage: Load this file in Rails console
#
# Example:
#   load 'lib/console/smc_example.rb'
#   fetch_nifty_and_sensex_candles

# Load helpers first
load 'lib/console/smc_helpers.rb'

def fetch_nifty_and_sensex_candles
  Rails.logger.debug { "\n#{'=' * 80}" }
  Rails.logger.debug '  Fetching Candles for NIFTY and SENSEX'
  Rails.logger.debug '=' * 80

  # Fetch NIFTY
  Rails.logger.debug "\n📊 Fetching NIFTY candles..."
  nifty = Instrument.find_by_sid_and_segment(
    security_id: '13',
    segment_code: 'IDX_I',
    symbol_name: 'NIFTY'
  )

  if nifty
    Rails.logger.debug { "  Instrument: #{nifty.symbol_name} (ID: #{nifty.security_id})" }

    Rails.logger.debug '  Fetching 1H... '
    nifty_1h = fetch_candles_with_history(nifty, interval: '60', target_candles: 60, delay_seconds: 1.0)
    Rails.logger.debug { "#{nifty_1h&.candles&.count || 0} candles" }

    Rails.logger.debug '  Fetching 15m... '
    nifty_15m = fetch_candles_with_history(nifty, interval: '15', target_candles: 100, delay_seconds: 1.0)
    Rails.logger.debug { "#{nifty_15m&.candles&.count || 0} candles" }

    Rails.logger.debug '  Fetching 5m... '
    nifty_5m = fetch_candles_with_history(nifty, interval: '5', target_candles: 150, delay_seconds: 1.0)
    Rails.logger.debug { "#{nifty_5m&.candles&.count || 0} candles" }

    # Store in variables for easy access
    $nifty_1h = nifty_1h
    $nifty_15m = nifty_15m
    $nifty_5m = nifty_5m
  else
    Rails.logger.debug '  ❌ NIFTY instrument not found'
  end

  # Fetch SENSEX
  Rails.logger.debug "\n📊 Fetching SENSEX candles..."
  sensex = Instrument.find_by_sid_and_segment(
    security_id: '51',
    segment_code: 'IDX_I',
    symbol_name: 'SENSEX'
  )

  if sensex
    Rails.logger.debug { "  Instrument: #{sensex.symbol_name} (ID: #{sensex.security_id})" }

    Rails.logger.debug '  Fetching 1H... '
    sensex_1h = fetch_candles_with_history(sensex, interval: '60', target_candles: 60, delay_seconds: 1.0)
    Rails.logger.debug { "#{sensex_1h&.candles&.count || 0} candles" }

    Rails.logger.debug '  Fetching 15m... '
    sensex_15m = fetch_candles_with_history(sensex, interval: '15', target_candles: 100, delay_seconds: 1.0)
    Rails.logger.debug { "#{sensex_15m&.candles&.count || 0} candles" }

    Rails.logger.debug '  Fetching 5m... '
    sensex_5m = fetch_candles_with_history(sensex, interval: '5', target_candles: 150, delay_seconds: 1.0)
    Rails.logger.debug { "#{sensex_5m&.candles&.count || 0} candles" }

    # Store in variables for easy access
    $sensex_1h = sensex_1h
    $sensex_15m = sensex_15m
    $sensex_5m = sensex_5m
  else
    Rails.logger.debug '  ❌ SENSEX instrument not found'
  end

  Rails.logger.debug { "\n#{'=' * 80}" }
  Rails.logger.debug '  Available Variables:'
  Rails.logger.debug '=' * 80
  Rails.logger.debug '  NIFTY:  $nifty_1h, $nifty_15m, $nifty_5m'
  Rails.logger.debug '  SENSEX: $sensex_1h, $sensex_15m, $sensex_5m'
  Rails.logger.debug "\nExample usage:"
  Rails.logger.debug '  Smc::Context.new($nifty_1h)'
  Rails.logger.debug '  Smc::BiasEngine.new(nifty).details'
  Rails.logger.debug "\n"
end

Rails.logger.debug { "\n#{'=' * 80}" }
Rails.logger.debug '  SMC Example Script Loaded'
Rails.logger.debug '=' * 80
Rails.logger.debug "\nRun: fetch_nifty_and_sensex_candles"
Rails.logger.debug "\n"

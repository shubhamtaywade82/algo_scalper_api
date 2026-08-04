# frozen_string_literal: true

# SMC Console Example - Fetch candles for NIFTY and SENSEX
# Usage (Rails console):
#
#   Console::SmcExample.fetch_nifty_and_sensex_candles
#
module Console
  module SmcExample
    module_function

    def fetch_nifty_and_sensex_candles
      require_relative 'smc_helpers'

      Rails.logger.debug { "\n#{'=' * 80}" }
      Rails.logger.debug '  Fetching Candles for NIFTY and SENSEX'
      Rails.logger.debug '=' * 80

      fetch_for(symbol_name: 'NIFTY', security_id: '13')
      fetch_for(symbol_name: 'SENSEX', security_id: '51')

      Rails.logger.debug { "\n#{'=' * 80}" }
      Rails.logger.debug '  Available Variables:'
      Rails.logger.debug '=' * 80
      Rails.logger.debug '  NIFTY:  $nifty_1h, $nifty_15m, $nifty_5m'
      Rails.logger.debug '  SENSEX: $sensex_1h, $sensex_15m, $sensex_5m'
      Rails.logger.debug "\n"
    end

    def fetch_for(symbol_name:, security_id:)
      Rails.logger.debug "\n📊 Fetching #{symbol_name} candles..."

      instrument = Instrument.find_by_sid_and_segment(
        security_id: security_id,
        segment_code: 'IDX_I',
        symbol_name: symbol_name
      )

      unless instrument
        Rails.logger.debug "  ❌ #{symbol_name} instrument not found"
        return
      end

      Rails.logger.debug { "  Instrument: #{instrument.symbol_name} (ID: #{instrument.security_id})" }

      candles_1h = fetch_candles_with_history(instrument, interval: '60', target_candles: 60, delay_seconds: 1.0)
      candles_15m = fetch_candles_with_history(instrument, interval: '15', target_candles: 100, delay_seconds: 1.0)
      candles_5m = fetch_candles_with_history(instrument, interval: '5', target_candles: 150, delay_seconds: 1.0)

      store(symbol_name: symbol_name, candles_1h: candles_1h, candles_15m: candles_15m, candles_5m: candles_5m)
    end
    private_class_method :fetch_for

    def store(symbol_name:, candles_1h:, candles_15m:, candles_5m:)
      case symbol_name
      when 'NIFTY'
        $nifty_1h = candles_1h
        $nifty_15m = candles_15m
        $nifty_5m = candles_5m
      when 'SENSEX'
        $sensex_1h = candles_1h
        $sensex_15m = candles_15m
        $sensex_5m = candles_5m
      end
    end
    private_class_method :store
  end
end

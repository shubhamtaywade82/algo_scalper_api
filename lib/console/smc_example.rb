# frozen_string_literal: true

# SMC Console Example - Fetch candles for NIFTY and SENSEX
# Usage: Load this file in Rails console
#
#   Console::SmcExample.fetch_nifty_and_sensex_candles
#
# NOTE: Must always define Console::SmcExample so Zeitwerk eager load works
# (bin/jobs, production boot). Behavior is gated inside the method.
module Console
  module SmcExample
    module_function

    def fetch_nifty_and_sensex_candles
      unless console_demo_allowed?
        Rails.logger.debug { '[Console::SmcExample] Skipped (use in development/test console only)' }
        return
      end

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

    def console_demo_allowed?
      Rails.env.local?
    end
    private_class_method :console_demo_allowed?

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

      candles_1h = Console::SmcHelpers.fetch_candles_with_history(
        instrument, interval: '60', target_candles: 60, delay_seconds: 1.0
      )
      candles_15m = Console::SmcHelpers.fetch_candles_with_history(
        instrument, interval: '15', target_candles: 100, delay_seconds: 1.0
      )
      candles_5m = Console::SmcHelpers.fetch_candles_with_history(
        instrument, interval: '5', target_candles: 150, delay_seconds: 1.0
      )

      store(symbol_name: symbol_name, candles_1h: candles_1h, candles_15m: candles_15m, candles_5m: candles_5m)
    end
    private_class_method :fetch_for

    def store(symbol_name:, candles_1h:, candles_15m:, candles_5m:)
      # rubocop:disable Style/GlobalVars -- console-only scratch vars ($nifty_*, $sensex_*)
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
      # rubocop:enable Style/GlobalVars
    end
    private_class_method :store
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

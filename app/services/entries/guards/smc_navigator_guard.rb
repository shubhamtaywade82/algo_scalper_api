# frozen_string_literal: true

module Entries
  module Guards
    # LTF SMC overlay (zone + liquidity + swing trend). Runs after LTP resolution.
    class SmcNavigatorGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if AlgoConfig.run_mode == 'exit_testing'
          return EntryGuardPipeline::PASS unless overlay_enabled?

          instrument = context[:instrument]
          direction = context[:direction]
          price = underlying_reference_price(instrument)

          result = Smc::Navigator.evaluate_entry(
            price: price,
            direction: direction,
            instrument: instrument
          )

          return { blocked: "smc_navigator:#{result.reason}" } unless result.allow

          min = min_confidence
          return EntryGuardPipeline::PASS if result.confidence >= min

          { blocked: 'smc_navigator:low_confidence' }
        end

        private

        def overlay_enabled?
          cfg = AlgoConfig.fetch[:signals] || {}
          cfg[:enable_smc_navigator_overlay] == true
        rescue StandardError
          false
        end

        def min_confidence
          cfg = AlgoConfig.fetch[:signals] || {}
          v = cfg[:smc_navigator_min_confidence]
          v&.to_f&.positive? ? v.to_f : 0.6
        rescue StandardError
          0.6
        end

        def underlying_reference_price(instrument)
          return nil unless instrument

          series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)
          series&.candles&.last&.close&.to_f
        rescue StandardError
          nil
        end
      end
    end
  end
end

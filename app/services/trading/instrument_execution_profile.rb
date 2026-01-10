# frozen_string_literal: true

module Trading
  class InstrumentExecutionProfile
    class UnsupportedInstrumentError < StandardError; end

    PROFILES = {
      'NIFTY' => {
        allow_execution_only: true,
        max_lots_by_permission: {
          execution_only: 1,
          scale_ready: 2,
          full_deploy: 4
        }.freeze,
        holding_rules: {
          scalp_seconds: (30..180),
          trend_minutes: (10..45),
          stall_candles_5m: (3..5)
        }.freeze,
        target_model: :absolute,
        scaling_style: :early
      }.freeze,
      'SENSEX' => {
        allow_execution_only: false,
        max_lots_by_permission: {
          execution_only: 0,
          scale_ready: 1,
          full_deploy: 3
        }.freeze,
        holding_rules: {
          trend_minutes: (30..90),
          allow_early_stagnation: true
        }.freeze,
        target_model: :convexity,
        scaling_style: :late
      }.freeze
    }.freeze

    class << self
      # @param symbol [String, Symbol]
      # @return [Hash] frozen profile hash
      def for(symbol)
        key = normalize_symbol(symbol)
        profile = PROFILES[key]
        raise UnsupportedInstrumentError, "Unsupported instrument: #{symbol}" unless profile

        profile
      end

      private

      def normalize_symbol(symbol)
        symbol.to_s.strip.upcase
      end
    end
  end
end


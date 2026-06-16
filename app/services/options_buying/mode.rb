# frozen_string_literal: true

module OptionsBuying
  class Mode
    INTRADAY = 'intraday_scalper'
    POSITIONAL = 'positional'

    class << self
      def config
        AlgoConfig.fetch[:options_buying] || {}
      rescue StandardError
        {}
      end

      def intraday?
        config[:mode].to_s != POSITIONAL
      end

      def positional_active?
        config[:mode].to_s == POSITIONAL && config.dig(:positional, :enabled) == true
      end

      def breakout_enabled?
        config.dig(:breakout, :enabled) != false
      end

      def compression_enabled?
        config.dig(:atr_compression, :enabled) != false
      end

      def chain_radar_enabled?
        config.dig(:chain_radar, :enabled) != false
      end

      def rsi_bias_enabled?
        config.dig(:rsi_bias, :enabled) != false
      end

      def streams_enabled?
        config.dig(:streams, :enabled) != false
      end

      def telemetry_sink_enabled?
        config.dig(:streams, :telemetry_sink_enabled) != false
      end
    end
  end
end

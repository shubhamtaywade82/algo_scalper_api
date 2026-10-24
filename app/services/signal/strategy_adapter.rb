# frozen_string_literal: true

module Signal
  # Adapter connecting domain strategies to Signal::Engine
  class StrategyAdapter
    class << self
      def analyze_with_strategy(strategy_class:, series:, index: -1, strategy_config: {})
        instance = strategy_class.new(series: series, **strategy_config)
        raw_signal = instance.generate_signal(index)

        if raw_signal.blank? || raw_signal[:action] == :no_signal
          return { status: :ok, series: series, direction: :avoid }
        end

        direction = strategy_to_direction(raw_signal[:action])
        confidence = raw_signal[:confidence] || 70.0
        last_ts = series.candles.last&.timestamp

        {
          status: :ok,
          series: series,
          direction: direction,
          confidence: confidence,
          last_candle_timestamp: last_ts,
          raw_signal: raw_signal
        }
      rescue StandardError => e
        Rails.logger.error("[Signal::StrategyAdapter] Error running #{strategy_class}: #{e.message}")
        { status: :error, message: e.message }
      end

      private

      def strategy_to_direction(action)
        case action
        when :buy_call, :call, :ce, :bullish
          :bullish
        when :buy_put, :put, :pe, :bearish
          :bearish
        else
          :avoid
        end
      end
    end
  end
end

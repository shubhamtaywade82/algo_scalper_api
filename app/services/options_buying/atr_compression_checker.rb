# frozen_string_literal: true

module OptionsBuying
  # Service to calculate ATR and check setup compression ratio for options buying setup.
  class ATRCompressionChecker
    class << self
      def compressed?(instrument)
        ratio = setup_ratio(instrument)
        return false if ratio.nil?

        max_ratio = Mode.config.dig(:atr_compression, :max_setup_ratio) || 0.30
        ratio <= max_ratio
      end

      def setup_ratio(instrument)
        key = instrument_key(instrument)
        return nil if key.blank?

        atr = compute_daily_atr_for(instrument)
        return nil if atr.nil? || atr.zero?

        candles = StateStore.index_candles(key, '15')
        return nil if candles.blank?

        highs = candles.map { |c| c[:high].to_f }
        lows = candles.map { |c| c[:low].to_f }
        setup_range = highs.max - lows.min
        setup_range / atr.to_f
      rescue StandardError => e
        Rails.logger.warn("[ATRCompressionChecker] setup_ratio failed for #{instrument}: #{e.message}")
        nil
      end

      def compute_daily_atr_for(instrument)
        key = instrument_key(instrument)
        return nil if key.blank?

        period = Mode.config.dig(:atr_compression, :atr_period) || 14
        candles = StateStore.index_candles(key, 'D')
        return nil if candles.blank? || candles.size < period

        highs = candles.map { |c| c[:high].to_f }
        lows = candles.map { |c| c[:low].to_f }
        closes = candles.map { |c| c[:close].to_f }

        tr_values = Array.new(candles.size)
        candles.size.times do |i|
          if i.zero?
            tr_values[i] = highs[i] - lows[i]
          else
            tr_values[i] = [
              highs[i] - lows[i],
              (highs[i] - closes[i - 1]).abs,
              (lows[i] - closes[i - 1]).abs
            ].max
          end
        end

        tr_values.last(period).sum / period.to_f
      rescue StandardError => e
        Rails.logger.warn("[ATRCompressionChecker] compute_daily_atr_for failed for #{instrument}: #{e.message}")
        nil
      end

      private

      def instrument_key(instrument)
        if instrument.respond_to?(:symbol_name)
          instrument.symbol_name
        elsif instrument.respond_to?(:to_s)
          instrument.to_s.upcase
        end
      end
    end
  end
end

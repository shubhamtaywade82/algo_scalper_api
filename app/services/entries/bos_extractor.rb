# frozen_string_literal: true

module Entries
  # Extracts confirmed BOS events deterministically from a CandleSeries.
  # BOS = close-based break of a confirmed swing level.
  class BosExtractor
    class << self
      def last_confirmed_bos(series, lookback: 5)
        return nil unless series&.candles&.any?

        swings = detect_swings(series, lookback: lookback)
        return nil if swings.size < 2

        bos_events = build_bos_events(series, swings)
        return nil if bos_events.empty?

        bos_events.max_by { |event| event[:confirmed_index] }
      end

      def bos_id(timeframe:, confirmed_at:, direction:)
        ts = confirmed_at.respond_to?(:to_i) ? confirmed_at.to_i : confirmed_at.to_s.to_i
        "#{timeframe}-#{ts}-#{direction}"
      end

      private

      def detect_swings(series, lookback:)
        candles = series.candles
        candles.each_with_index.filter_map do |candle, idx|
          if series.swing_high?(idx, lookback)
            swing_payload(:high, candle.high, idx, candle.timestamp)
          elsif series.swing_low?(idx, lookback)
            swing_payload(:low, candle.low, idx, candle.timestamp)
          end
        end
      end

      def build_bos_events(series, swings)
        candles = series.candles
        events = []

        swings.each_with_index do |swing, idx|
          prev = idx.positive? ? swings[idx - 1] : nil
          next unless prev

          if swing[:type] == :high && prev[:type] == :low
            confirm_idx = confirmation_index_for(series, swing, :bullish)
            next unless confirm_idx

            events << build_event(
              direction: :bullish,
              broken_swing: swing,
              origin_swing: prev,
              confirmed_index: confirm_idx,
              confirmed_at: candles[confirm_idx]&.timestamp
            )
          elsif swing[:type] == :low && prev[:type] == :high
            confirm_idx = confirmation_index_for(series, swing, :bearish)
            next unless confirm_idx

            events << build_event(
              direction: :bearish,
              broken_swing: swing,
              origin_swing: prev,
              confirmed_index: confirm_idx,
              confirmed_at: candles[confirm_idx]&.timestamp
            )
          end
        end

        events
      end

      def confirmation_index_for(series, swing, direction)
        candles = series.candles
        start_idx = swing[:index] + 1
        return nil if start_idx >= candles.size

        (start_idx...candles.size).each do |idx|
          close = candles[idx]&.close
          next unless close

          return idx if direction == :bullish && close > swing[:price]
          return idx if direction == :bearish && close < swing[:price]
        end

        nil
      end

      def build_event(direction:, broken_swing:, origin_swing:, confirmed_index:, confirmed_at:)
        {
          direction: direction,
          broken_swing: broken_swing,
          origin_swing: origin_swing,
          confirmed_index: confirmed_index,
          confirmed_at: confirmed_at
        }
      end

      def swing_payload(type, price, index, timestamp)
        {
          type: type,
          price: price,
          index: index,
          time: timestamp
        }
      end
    end
  end
end

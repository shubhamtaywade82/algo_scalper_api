require "time"

module BacktestEngine
  module Market
    class Candle
      ATTRS = %i[
        timestamp open high low close volume open_interest
      ].freeze

      attr_reader(*ATTRS)

      def initialize(
        timestamp:,
        open:,
        high:,
        low:,
        close:,
        volume: 0,
        open_interest: nil
      )
        @timestamp = normalize_time(timestamp)
        @open = to_f!(open, :open)
        @high = to_f!(high, :high)
        @low = to_f!(low, :low)
        @close = to_f!(close, :close)
        @volume = volume.to_i
        @open_interest = open_interest&.to_f

        validate_ohlc!
      end

      # Core candle properties

      def bullish?
        close > open
      end

      def bearish?
        close < open
      end

      def doji?(threshold: 0.1)
        return false if range.zero?

        body_size <= range * threshold
      end

      def body_size
        (close - open).abs
      end

      def range
        high - low
      end

      def upper_wick
        high - [open, close].max
      end

      def lower_wick
        [open, close].min - low
      end

      def midpoint
        (high + low) / 2.0
      end

      # Structure helpers

      def higher_high_than?(other)
        high > other.high
      end

      def lower_low_than?(other)
        low < other.low
      end

      def engulfs?(other)
        high >= other.high && low <= other.low
      end

      def inside_bar?(other)
        high <= other.high && low >= other.low
      end

      # Momentum / strength

      def strong_bullish?(min_body_ratio: 0.6)
        return false if range.zero?

        bullish? && body_size / range >= min_body_ratio
      end

      def strong_bearish?(min_body_ratio: 0.6)
        return false if range.zero?

        bearish? && body_size / range >= min_body_ratio
      end

      def rejection_wick?(wick_ratio: 0.5)
        return false if range.zero?

        upper_wick / range >= wick_ratio || lower_wick / range >= wick_ratio
      end

      # Comparable by timestamp

      include Comparable

      def <=>(other)
        timestamp <=> other.timestamp
      end

      # Serialization

      def to_h
        {
          timestamp: timestamp,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
          open_interest: open_interest
        }
      end

      def to_s
        "#<Candle #{timestamp} O:#{open} H:#{high} L:#{low} C:#{close}>"
      end

      # Builders

      def self.from_hash(hash)
        new(
          timestamp: hash[:timestamp] || hash["timestamp"],
          open: hash[:open] || hash["open"],
          high: hash[:high] || hash["high"],
          low: hash[:low] || hash["low"],
          close: hash[:close] || hash["close"],
          volume: hash[:volume] || hash["volume"],
          open_interest: hash[:open_interest] || hash["open_interest"]
        )
      end

      def self.build_series(array)
        Array(array).map { |item| from_hash(item) }.sort
      end

      private

      def validate_ohlc!
        raise ArgumentError, "Invalid OHLC" if high < low
        raise ArgumentError, "Open outside range" unless between?(open)
        raise ArgumentError, "Close outside range" unless between?(close)
      end

      def between?(price)
        price >= low && price <= high
      end

      def normalize_time(value)
        return value if value.is_a?(Time)
        return Time.at(value) if value.is_a?(Integer)

        string = value.to_s.strip
        return Time.at(string.to_i) if string.match?(/\A\d+\z/)

        Time.parse(string)
      end

      def to_f!(value, field)
        Float(value)
      rescue StandardError
        raise ArgumentError, "Invalid #{field}: #{value}"
      end
    end
  end
end


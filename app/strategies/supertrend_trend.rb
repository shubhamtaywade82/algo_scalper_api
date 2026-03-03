# frozen_string_literal: true

# Supertrend-only entry strategy: direction from status on the current bar.
# - bullish trend → :long (CE)
# - bearish trend → :short (PE)
# - no data → :none (no trade)
#
# No capital, order, exit, or confirmation logic. Used only for entry direction.
class SupertrendTrend
  class << self
    # @param series [Object] Candle series with #candles (array of candles with #close)
    # @param supertrend_result [Hash] Must have :line (array of values, same length as candles)
    # @return [Symbol] :long, :short, or :none
    def direction(series:, supertrend_result:)
      return :none if series.blank? || supertrend_result.blank?

      line = supertrend_result[:line]
      return :none unless line.is_a?(Array) && line.any?

      closes = closes_from_series(series)
      return :none if closes.blank? || closes.size != line.size

      last_i = last_valid_index(line)
      return :none if last_i.nil?

      current_trend = trend_at(closes, line, last_i)
      return :none if current_trend.nil?

      current_trend == :bullish ? :long : :short
    end

    private

    def closes_from_series(series)
      return [] unless series

      if series.respond_to?(:closes)
        series.closes
      elsif series.respond_to?(:candles) && series.candles.respond_to?(:map)
        series.candles.map { |c| c.respond_to?(:close) ? c.close : nil }
      else
        []
      end
    end

    def last_valid_index(line)
      return nil unless line.is_a?(Array)

      (line.size - 1).downto(0) do |i|
        return i unless line[i].nil?
      end
      nil
    end

    def trend_at(closes, line, idx)
      return nil if idx.negative? || idx >= closes.size || idx >= line.size

      close_val = closes[idx]
      line_val = line[idx]
      return nil if close_val.nil? || line_val.nil?

      close_val >= line_val ? :bullish : :bearish
    end
  end
end

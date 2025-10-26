# frozen_string_literal: true

require 'bigdecimal'

module Trading
  # Simple, fast signal generator placeholder
  # Replace with robust indicator logic as you iterate
  class TrendIdentifier
    def initialize(fetcher: Trading::DataFetcherService.new)
      @fetcher = fetcher
    end

    # Returns :long, :short or nil
    def signal_for(instrument, interval: '5minute', lookback: 50)
      data = @fetcher.fetch_historical_data(
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        interval: interval,
        lookback: lookback
      )

      closes = extract_closes(data)
      return nil if closes.length < 3

      # Naive momentum: last close above previous and simple MA trending up
      last = closes[-1]
      prev = closes[-2]
      sma_fast = average(closes.last(5))
      sma_slow = average(closes.last(20))

      :long if last && prev && sma_fast && sma_slow && last > prev && sma_fast >= sma_slow
    rescue StandardError => e
      Rails.logger.warn("[TrendIdentifier] failed for #{instrument.symbol_name}: #{e.class} - #{e.message}")
      nil
    end

    private

    def extract_closes(payload)
      # Supports hash-of-arrays or array-of-bars
      if payload.is_a?(Hash)
        arr = payload[:close] || payload['close']
        return Array(arr).map { |v| to_f(v) }
      elsif payload.is_a?(Array)
        return payload.filter_map do |bar|
          next unless bar.is_a?(Hash)

          to_f(bar[:close] || bar['close'])
        end
      end
      []
    end

    def average(arr)
      return nil if arr.empty?

      arr.compact!
      return nil if arr.empty?

      arr.sum(0.0) / arr.size
    end

    def to_f(val)
      return nil if val.nil?

      Float(val, exception: false)
    end
  end
end

# frozen_string_literal: true

module Trading
  class TrendIdentifier
    def initialize(data_fetcher: DataFetcherService.new)
      @data_fetcher = data_fetcher
    end

    def signal_for(instrument)
      candles = @data_fetcher.fetch_historical_data(
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        interval: '5minute',
        lookback: 120
      )
      return if candles.blank?

      closes = candles.filter_map { |candle| candle[:close] }.map { |value| BigDecimal(value.to_s) }
      return if closes.size < 30

      rsi_value = Indicators.rsi(closes)
      supertrend = Indicators.supertrend(candles.last(20))
      sma_fast = simple_moving_average(closes.last(9))
      sma_slow = simple_moving_average(closes.last(21))

      bullish = supertrend && supertrend[:trend] == :bullish
      momentum = sma_fast && sma_slow && sma_fast > sma_slow
      rsi_confirmed = rsi_value&.between?(BigDecimal(40), BigDecimal(70))

      return :long if bullish && momentum && rsi_confirmed

      nil
    end

    private

    def simple_moving_average(values)
      values = Array(values).compact
      return if values.empty?

      values.sum / values.size
    end
  end
end

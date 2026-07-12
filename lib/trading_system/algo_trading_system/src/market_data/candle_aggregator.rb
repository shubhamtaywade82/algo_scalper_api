# frozen_string_literal: true

require_relative 'candle'

module MarketData
  # Aggregates ticks into candles of a specific interval
  class CandleAggregator
    attr_reader :interval_seconds, :current_candle

    def initialize(interval_minutes: 1)
      @interval_seconds = interval_minutes * 60
      @current_candle = nil
      @on_candle_close_blocks = []
    end

    def on_candle_close(&block)
      @on_candle_close_blocks << block
    end

    def process_tick(tick)
      timestamp = tick.timestamp.to_i
      bucket_start = (timestamp / @interval_seconds) * @interval_seconds

      if @current_candle.nil?
        start_new_candle(tick, bucket_start)
      elsif bucket_start > @current_candle[:bucket_start]
        close_current_candle
        start_new_candle(tick, bucket_start)
      else
        update_current_candle(tick)
      end
    end

    private

    def start_new_candle(tick, bucket_start)
      @current_candle = {
        symbol: tick.symbol,
        timestamp: Time.at(bucket_start),
        bucket_start: bucket_start,
        open: tick.last_price,
        high: tick.last_price,
        low: tick.last_price,
        close: tick.last_price,
        volume: tick.last_quantity,
        iv: 0.0, # Will be filled if available
        spot: 0.0
      }
    end

    def update_current_candle(tick)
      @current_candle[:high] = [@current_candle[:high], tick.last_price].max
      @current_candle[:low] = [@current_candle[:low], tick.last_price].min
      @current_candle[:close] = tick.last_price
      @current_candle[:volume] += tick.last_quantity
    end

    def close_current_candle
      candle = OpenStruct.new(@current_candle)
      @on_candle_close_blocks.each { |b| b.call(candle) }
    end
  end
end

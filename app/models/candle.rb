# frozen_string_literal: true

class Candle
  attr_reader :timestamp, :open, :high, :low, :close, :volume

  def initialize(ts:, open:, high:, low:, close:, volume:)
    @timestamp = ts
    @open = open.to_f
    @high = high.to_f
    @low = low.to_f
    @close = close.to_f
    @volume = volume.to_i
  end

  def bullish?
    close >= open
  end

  def bearish?
    close < open
  end
end

# frozen_string_literal: true

class Candle
  attr_reader :timestamp, :open, :high, :low, :close, :volume

  # rubocop:disable Metrics/ParameterLists
  def initialize(timestamp:, open:, high:, low:, close:, volume:)
    @timestamp = timestamp
    @open = open.to_f
    @high = high.to_f
    @low = low.to_f
    @close = close.to_f
    @volume = volume.to_i
  end
  # rubocop:enable Metrics/ParameterLists

  def bullish?
    close >= open
  end

  def bearish?
    close < open
  end
end

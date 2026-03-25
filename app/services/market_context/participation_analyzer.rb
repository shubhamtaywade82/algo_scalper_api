# frozen_string_literal: true

module MarketContext
  # Volume participation vs recent baseline (institutional interest proxy).
  class ParticipationAnalyzer
    Result = Struct.new(:level, :volume_ratio, keyword_init: true) # rubocop:disable Style/RedundantStructKeywordInit

    WINDOW = 20
    HIGH_RATIO = 1.5
    LOW_RATIO = 0.7

    def initialize(series:)
      @series = series
    end

    def call
      candles = @series.candles
      return Result.new(level: :normal, volume_ratio: nil) if candles.size < 5

      @series.ensure_sorted!
      last_vol = candles.last.volume.to_f
      window = candles.last([candles.size, WINDOW].min)
      baseline = window[0..-2]
      return Result.new(level: :normal, volume_ratio: nil) if baseline.size < 3

      avg_vol = baseline.sum(&:volume).to_f / baseline.size
      return Result.new(level: :normal, volume_ratio: nil) unless avg_vol.positive?

      ratio = last_vol / avg_vol
      level = if ratio >= HIGH_RATIO
                :high
              elsif ratio <= LOW_RATIO
                :low
              else
                :normal
              end

      Result.new(level: level, volume_ratio: ratio.round(4))
    end
  end
end

# frozen_string_literal: true

module Entries
  # Scores whether the underlying is too choppy for 1m Supertrend option buying.
  # Higher scores mean more range noise; callers should block entries at/above
  # the configured threshold.
  class ChopScore
    DEFAULTS = {
      enabled: true,
      block_threshold: 5,
      caution_threshold: 3,
      adx_threshold: 20.0,
      supertrend_flip_limit: 3,
      supertrend_window_candles: 15,
      opening_range_min_points: { NIFTY: 50, BANKNIFTY: 150, SENSEX: 150 },
      bb_width_threshold: 0.005
    }.freeze

    # @param index_key [String, Symbol] index name such as NIFTY or SENSEX
    # @param series_1m [CandleSeries] one-minute candles
    # @param series_5m [CandleSeries] five-minute candles
    # @param series_15m [CandleSeries] fifteen-minute candles
    # @param config [Hash] optional config override
    def initialize(index_key:, series_1m:, series_5m:, series_15m:, config: {})
      @index_key = index_key.to_s.upcase
      @series_1m = series_1m
      @series_5m = series_5m
      @series_15m = series_15m
      @config = DEFAULTS.deep_merge(config || {})
    end

    # @return [Hash] score, action, and reasons for audit logging
    def call
      score = 0
      reasons = []

      score, reasons = add(score, reasons, 2, '5m ADX below trend threshold') if low_adx?
      score, reasons = add(score, reasons, 2, '1m Supertrend flipped too often') if noisy_supertrend?
      score, reasons = add(score, reasons, 1, 'opening range too narrow') if narrow_opening_range?
      score, reasons = add(score, reasons, 2, '5m/15m Supertrend disagree') if higher_timeframes_disagree?
      score, reasons = add(score, reasons, 1, '5m Bollinger width compressed') if bollinger_squeeze?

      { score: score, action: action_for(score), reasons: reasons }
    end

    private

    attr_reader :index_key, :series_1m, :series_5m, :series_15m, :config

    def add(score, reasons, points, reason)
      [score + points, reasons + [reason]]
    end

    def action_for(score)
      return :block if score >= config[:block_threshold].to_i
      return :caution if score >= config[:caution_threshold].to_i

      :allow
    end

    def low_adx?
      adx = series_5m&.adx(14)
      adx && adx.to_f < config[:adx_threshold].to_f
    end

    def noisy_supertrend?
      trends = recent_supertrend_directions(series_1m, config[:supertrend_window_candles].to_i)
      return false if trends.size < 2

      flips = trends.each_cons(2).count { |left, right| left != right }
      flips >= config[:supertrend_flip_limit].to_i
    end

    def narrow_opening_range?
      candles = series_1m&.candles&.select do |candle|
        ist = candle.timestamp.in_time_zone('Asia/Kolkata')
        ist.strftime('%H:%M').between?('09:15', '09:30')
      end
      return false if candles.blank?

      points = candles.map(&:high).max.to_f - candles.map(&:low).min.to_f
      points < opening_range_min_points
    end

    def opening_range_min_points
      raw = config[:opening_range_min_points] || {}
      (raw[index_key.to_sym] || raw[index_key] || 50).to_f
    end

    def higher_timeframes_disagree?
      five = last_supertrend_direction(series_5m)
      fifteen = last_supertrend_direction(series_15m)
      five && fifteen && five != fifteen
    end

    def bollinger_squeeze?
      closes = Array(series_5m&.closes).last(20)
      return false if closes.size < 20

      mean = closes.sum.to_f / closes.size
      return false unless mean.positive?

      variance = closes.sum { |close| (close.to_f - mean)**2 } / closes.size
      sd = Math.sqrt(variance)
      width = (4.0 * sd) / mean
      width < config[:bb_width_threshold].to_f
    end

    def recent_supertrend_directions(series, count)
      st = supertrend(series)
      line = Array(st[:line])
      closes = Array(series&.closes)
      return [] if line.blank? || closes.blank?

      line.each_index.to_a.last(count).filter_map do |idx|
        next if line[idx].nil? || closes[idx].nil?

        closes[idx].to_f >= line[idx].to_f ? :bullish : :bearish
      end
    end

    def last_supertrend_direction(series)
      SupertrendTrend.direction(series: series, supertrend_result: supertrend(series))
    end

    def supertrend(series)
      return { line: [] } unless series&.candles&.any?

      cfg = AlgoConfig.fetch.dig(:signals, :supertrend) || {}
      Indicators::Supertrend.new(series: series, **cfg).call
    end
  end
end

# frozen_string_literal: true

# rubocop:disable Style/GlobalVars
module Optimization
  # Optimizes a SINGLE indicator's parameters
  # Tests parameter combinations for one indicator and measures price movement after signals
  class SingleIndicatorOptimizer
    INDICATOR_PARAM_SPACES = {
      adx: {
        period: [10, 14, 18],
        threshold: [15, 18, 20, 22, 25]
      },
      rsi: {
        period: [10, 14, 21],
        oversold: [20, 25, 30, 35],
        overbought: [65, 70, 75, 80]
      },
      macd: {
        fast: [8, 12, 14],
        slow: [20, 26, 30],
        signal: [5, 9, 12]
      },
      supertrend: {
        atr_period: [8, 10, 12, 14],
        multiplier: [1.5, 2.0, 2.5, 3.0]
      }
    }.freeze
    UPSERT_UNIQUE_BY_WITH_INDICATOR = %i[instrument_id interval indicator].freeze

    def initialize(instrument:, interval:, indicator:, lookback_days: 45, dry_run: false)
      @instrument = instrument
      @interval = interval
      @lookback = lookback_days
      @indicator = indicator.to_sym
      @dry_run = dry_run

      return if INDICATOR_PARAM_SPACES.key?(@indicator)

      raise ArgumentError, "Unknown indicator: #{@indicator}. Must be one of: #{INDICATOR_PARAM_SPACES.keys.join(', ')}"
    end

    def run
      log("[SingleIndicatorOptimizer] Optimizing #{@indicator} for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)")

      load_series!
      return { error: 'Failed to load series' } unless @series&.candles&.any?

      log("[SingleIndicatorOptimizer] Loaded #{@series.candles.size} candles")

      best = { score: -Float::INFINITY, params: nil, metrics: nil }
      total_combinations = param_combinations.size
      processed = 0

      log("[SingleIndicatorOptimizer] Testing #{total_combinations} parameter combinations...")

      param_combinations.each do |candidate|
        processed += 1
        metrics = backtest_indicator(candidate)

        next unless metrics && metrics[:avg_price_move]

        # Score based on average price movement after signals
        score = metrics[:avg_price_move].to_f

        if score > best[:score]
          best = { score: score, params: candidate, metrics: metrics }

          log(
            "[SingleIndicatorOptimizer] New best: AvgMove=#{score.round(4)}%, Signals=#{metrics[:total_signals]}, " \
            "WinRate=#{metrics[:win_rate]&.round(3)} (#{processed}/#{total_combinations})"
          )

          persist(best)
        end

        # Progress logging every 10%
        next unless (processed % [total_combinations / 10, 1].max).zero?

        progress_pct = (processed.to_f / total_combinations * 100).round(1)
        log("[SingleIndicatorOptimizer] Progress: #{progress_pct}% (#{processed}/#{total_combinations})")
      end

      log("[SingleIndicatorOptimizer] Optimization complete. Best AvgMove: #{best[:score]&.round(4)}%")
      best
    rescue StandardError => e
      Rails.logger.error("[SingleIndicatorOptimizer] Optimization failed: #{e.class} - #{e.message}")
      Rails.logger.error("[SingleIndicatorOptimizer] Backtrace: #{e.backtrace.first(5).join(', ')}")
      { error: e.message }
    end

    private

    def log(msg, level: :info)
      Rails.logger.public_send(level, msg)
      $stdout.puts msg
      $stdout.flush
    end

    def load_series!
      log("[SingleIndicatorOptimizer] Fetching intraday OHLC for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)")

      raw = @instrument.intraday_ohlc(
        interval: @interval,
        days: @lookback
      )

      if raw.blank?
        error_msg = "No intraday OHLC data returned for #{@instrument.symbol_name} @ #{@interval}m"
        log("[SingleIndicatorOptimizer] #{error_msg}", level: :error)
        return nil
      end

      log("[SingleIndicatorOptimizer] Received #{raw.is_a?(Hash) ? raw.keys.size : raw.size} records from API")

      @series = CandleSeries.new(symbol: @instrument.symbol_name, interval: @interval)
      @series.load_from_raw(raw)

      unless @series.candles.any?
        error_msg = "No candles loaded for #{@instrument.symbol_name} @ #{@interval}m (raw data: #{raw.class})"
        log("[SingleIndicatorOptimizer] #{error_msg}", level: :warn)
        return nil
      end

      log("[SingleIndicatorOptimizer] Successfully loaded #{@series.candles.size} candles")

      @series
    rescue StandardError => e
      error_msg = "Failed to load series: #{e.class} - #{e.message}"
      log("[SingleIndicatorOptimizer] #{error_msg}", level: :error)
      Rails.logger.error("[SingleIndicatorOptimizer] Backtrace: #{e.backtrace.first(5).join("\n")}")
      nil
    end

    def param_combinations
      @param_combinations ||= begin
        param_space = INDICATOR_PARAM_SPACES[@indicator]
        keys = param_space.keys
        values = param_space.values
        values.first.product(*values.drop(1)).map do |vals|
          keys.zip(vals).to_h
        end
      end
    end

    def backtest_indicator(params)
      Optimization::SingleIndicatorBacktester.new(
        series: @series,
        indicator: @indicator,
        params: params
      ).run
    rescue StandardError => e
      Rails.logger.warn("[SingleIndicatorOptimizer] Backtest failed for params #{params.inspect}: #{e.message}")
      nil
    end

    def persist(best)
      return if @dry_run
      return unless defined?(BestIndicatorParam)
      return unless best[:params] && best[:metrics]

      BestIndicatorParam.upsert( # rubocop:disable Rails/SkipsModelValidations
        {
          instrument_id: @instrument.id,
          interval: @interval,
          indicator: @indicator.to_s,
          params: best[:params],
          metrics: best[:metrics],
          score: best[:score],
          updated_at: Time.current
        },
        unique_by: UPSERT_UNIQUE_BY_WITH_INDICATOR
      )
    rescue StandardError => e
      Rails.logger.warn("[SingleIndicatorOptimizer] Failed to persist result: #{e.message}")
    end
  end
end

# rubocop:enable Style/GlobalVars

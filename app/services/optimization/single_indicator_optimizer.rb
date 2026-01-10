# frozen_string_literal: true

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

    def initialize(instrument:, interval:, indicator:, lookback_days: 45)
      @instrument = instrument
      @interval = interval
      @lookback = lookback_days
      @indicator = indicator.to_sym

      return if INDICATOR_PARAM_SPACES.key?(@indicator)

      raise ArgumentError, "Unknown indicator: #{@indicator}. Must be one of: #{INDICATOR_PARAM_SPACES.keys.join(', ')}"
    end

    def run
      Rails.logger.info("[SingleIndicatorOptimizer] Optimizing #{@indicator} for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)")
      $stdout.puts "[SingleIndicatorOptimizer] Optimizing #{@indicator} for #{@instrument.symbol_name} @ #{@interval}m"
      $stdout.flush

      load_series!
      return { error: 'Failed to load series' } unless @series&.candles&.any?

      Rails.logger.info("[SingleIndicatorOptimizer] Loaded #{@series.candles.size} candles")
      $stdout.puts "[SingleIndicatorOptimizer] Loaded #{@series.candles.size} candles"
      $stdout.flush

      best = { score: -Float::INFINITY, params: nil, metrics: nil }
      total_combinations = param_combinations.size
      processed = 0

      Rails.logger.info("[SingleIndicatorOptimizer] Testing #{total_combinations} parameter combinations...")
      $stdout.puts "[SingleIndicatorOptimizer] Testing #{total_combinations} parameter combinations..."
      $stdout.flush

      param_combinations.each do |candidate|
        processed += 1
        metrics = backtest_indicator(candidate)

        next unless metrics && metrics[:avg_price_move]

        # Score based on average price movement after signals
        score = metrics[:avg_price_move].to_f

        if score > best[:score]
          best = { score: score, params: candidate, metrics: metrics }

          Rails.logger.info(
            "[SingleIndicatorOptimizer] New best: AvgMove=#{score.round(4)}%, " \
            "Signals=#{metrics[:total_signals]}, " \
            "WinRate=#{metrics[:win_rate]&.round(3)} " \
            "(#{processed}/#{total_combinations})"
          )
          $stdout.puts "[SingleIndicatorOptimizer] New best: AvgMove=#{score.round(4)}%, Signals=#{metrics[:total_signals]} (#{processed}/#{total_combinations})"
          $stdout.flush

          persist(best)
        end

        # Progress logging every 10%
        next unless (processed % [total_combinations / 10, 1].max).zero?

        progress_pct = (processed.to_f / total_combinations * 100).round(1)
        Rails.logger.info("[SingleIndicatorOptimizer] Progress: #{progress_pct}% (#{processed}/#{total_combinations})")
        $stdout.puts "[SingleIndicatorOptimizer] Progress: #{progress_pct}% (#{processed}/#{total_combinations})"
        $stdout.flush
      end

      Rails.logger.info("[SingleIndicatorOptimizer] Optimization complete. Best AvgMove: #{best[:score].round(4)}%")
      $stdout.puts "[SingleIndicatorOptimizer] Optimization complete. Best AvgMove: #{best[:score]&.round(4)}%"
      $stdout.flush
      best
    rescue StandardError => e
      Rails.logger.error("[SingleIndicatorOptimizer] Optimization failed: #{e.class} - #{e.message}")
      Rails.logger.error("[SingleIndicatorOptimizer] Backtrace: #{e.backtrace.first(5).join(', ')}")
      { error: e.message }
    end

    private

    def load_series!
      Rails.logger.info("[SingleIndicatorOptimizer] Fetching intraday OHLC for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)")
      $stdout.puts '[SingleIndicatorOptimizer] Fetching intraday OHLC...'
      $stdout.flush

      raw = @instrument.intraday_ohlc(
        interval: @interval,
        days: @lookback
      )

      if raw.blank?
        error_msg = "No intraday OHLC data returned for #{@instrument.symbol_name} @ #{@interval}m"
        Rails.logger.error("[SingleIndicatorOptimizer] #{error_msg}")
        $stdout.puts "[SingleIndicatorOptimizer] ❌ #{error_msg}"
        $stdout.flush
        return nil
      end

      Rails.logger.info("[SingleIndicatorOptimizer] Received #{raw.is_a?(Hash) ? raw.keys.size : raw.size} records from API")
      $stdout.puts '[SingleIndicatorOptimizer] Received data from API'
      $stdout.flush

      @series = CandleSeries.new(symbol: @instrument.symbol_name, interval: @interval)
      @series.load_from_raw(raw)

      unless @series.candles.any?
        error_msg = "No candles loaded for #{@instrument.symbol_name} @ #{@interval}m (raw data: #{raw.class})"
        Rails.logger.warn("[SingleIndicatorOptimizer] #{error_msg}")
        $stdout.puts "[SingleIndicatorOptimizer] ⚠️  #{error_msg}"
        $stdout.flush
        return nil
      end

      Rails.logger.info("[SingleIndicatorOptimizer] Successfully loaded #{@series.candles.size} candles")
      $stdout.puts "[SingleIndicatorOptimizer] ✅ Loaded #{@series.candles.size} candles"
      $stdout.flush

      @series
    rescue StandardError => e
      error_msg = "Failed to load series: #{e.class} - #{e.message}"
      Rails.logger.error("[SingleIndicatorOptimizer] #{error_msg}")
      Rails.logger.error("[SingleIndicatorOptimizer] Backtrace: #{e.backtrace.first(5).join("\n")}")
      $stdout.puts "[SingleIndicatorOptimizer] ❌ #{error_msg}"
      $stdout.flush
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
      return unless defined?(BestIndicatorParam)
      return unless best[:params] && best[:metrics]

      # Check if indicator column exists (for backward compatibility)
      if BestIndicatorParam.column_names.include?('indicator')
        BestIndicatorParam.upsert(
          {
            instrument_id: @instrument.id,
            interval: @interval,
            indicator: @indicator.to_s,
            params: best[:params],
            metrics: best[:metrics],
            score: best[:score],
            updated_at: Time.current
          },
          unique_by: %i[instrument_id interval indicator]
        )
      else
        # Fallback for old schema
        BestIndicatorParam.upsert(
          {
            instrument_id: @instrument.id,
            interval: @interval,
            params: { indicator: @indicator.to_s, **best[:params] },
            metrics: best[:metrics],
            score: best[:score],
            updated_at: Time.current
          },
          unique_by: %i[instrument_id interval]
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[SingleIndicatorOptimizer] Failed to persist result: #{e.message}")
    end
  end
end

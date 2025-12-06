# frozen_string_literal: true

module Optimization
  class IndicatorOptimizer
    PARAM_SPACE = {
      adx_thresh: [18, 22, 25, 28],
      rsi_lo: [20, 25, 30],
      rsi_hi: [65, 70, 75],
      macd_fast: [8, 12, 14],
      macd_slow: [20, 26, 30],
      macd_signal: [5, 9, 12],
      st_atr: [8, 10, 12],
      st_mult: [1.5, 2.0, 2.5]
    }.freeze

    # Reduced parameter space for faster testing
    TEST_PARAM_SPACE = {
      adx_thresh: [22, 25],
      rsi_lo: [25, 30],
      rsi_hi: [70, 75],
      macd_fast: [12],
      macd_slow: [26],
      macd_signal: [9],
      st_atr: [10],
      st_mult: [2.0, 2.5]
    }.freeze

    def initialize(instrument:, interval:, lookback_days: 45, test_mode: false)
      @instrument = instrument
      @interval = interval
      @lookback = lookback_days
      @test_mode = test_mode
    end

    def run
      Rails.logger.info("[Optimization] Starting optimization for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)")
      $stdout.puts "[Optimization] Starting optimization for #{@instrument.symbol_name} @ #{@interval}m (#{@lookback} days)"
      $stdout.flush

      load_series!
      return { error: 'Failed to load series' } unless @series && @series.candles.any?

      Rails.logger.info("[Optimization] Loaded #{@series.candles.size} candles")
      $stdout.puts "[Optimization] Loaded #{@series.candles.size} candles"
      $stdout.flush

      best = { score: -Float::INFINITY, params: nil, metrics: nil }
      total_combinations = param_combinations.size
      processed = 0

      Rails.logger.info("[Optimization] Testing #{total_combinations} parameter combinations...")
      $stdout.puts "[Optimization] Testing #{total_combinations} parameter combinations..."
      $stdout.flush

      param_combinations.each do |candidate|
        processed += 1
        metrics = backtest(candidate)

        if processed <= 3 && !metrics
          Rails.logger.debug("[Optimization] Backtest returned nil for params #{candidate.inspect}")
        end

        next unless metrics && metrics[:sharpe]

        score = metrics[:sharpe].to_f

        if score > best[:score]
          best = { score: score, params: candidate, metrics: metrics }

          Rails.logger.info(
            "[Optimization] New best: Sharpe=#{score.round(3)}, " \
            "WR=#{metrics[:win_rate]&.round(3)}, " \
            "PnL=#{metrics[:net_pnl]&.round(2)} " \
            "(#{processed}/#{total_combinations})"
          )
          $stdout.puts "[Optimization] New best: Sharpe=#{score.round(3)}, WR=#{metrics[:win_rate]&.round(3)}, PnL=#{metrics[:net_pnl]&.round(2)} (#{processed}/#{total_combinations})"
          $stdout.flush

          persist(best)
        end

        # Progress logging every 10%
        if processed % [total_combinations / 10, 1].max == 0
          progress_pct = (processed.to_f / total_combinations * 100).round(1)
          Rails.logger.info("[Optimization] Progress: #{progress_pct}% (#{processed}/#{total_combinations})")
          $stdout.puts "[Optimization] Progress: #{progress_pct}% (#{processed}/#{total_combinations})"
          $stdout.flush
        end
      end

      Rails.logger.info("[Optimization] Optimization complete. Best Sharpe: #{best[:score].round(3)}")
      $stdout.puts "[Optimization] Optimization complete. Best Sharpe: #{best[:score].round(3)}"
      $stdout.flush
      best
    rescue StandardError => e
      Rails.logger.error("[Optimization] Optimization failed: #{e.class} - #{e.message}")
      Rails.logger.error("[Optimization] Backtrace: #{e.backtrace.first(5).join(', ')}")
      { error: e.message }
    end

    private

    def load_series!
      # Fetch historical data with explicit lookback period
      # Use intraday_ohlc directly to get more data than default cache
      raw = @instrument.intraday_ohlc(
        interval: @interval,
        days: @lookback
      )

      raise "No intraday OHLC for #{@instrument.symbol_name}" unless raw.present?

      @series = CandleSeries.new(symbol: @instrument.symbol_name, interval: @interval)
      @series.load_from_raw(raw)

      unless @series.candles.any?
        Rails.logger.warn("[Optimization] No candles loaded for #{@instrument.symbol_name} @ #{@interval}m")
        return nil
      end

      @series
    rescue StandardError => e
      Rails.logger.error("[Optimization] Failed to load series: #{e.class} - #{e.message}")
      nil
    end

    def param_combinations
      @param_combinations ||= begin
        param_space = @test_mode ? TEST_PARAM_SPACE : PARAM_SPACE
        keys = param_space.keys
        values = param_space.values
        values.first.product(*values.drop(1)).map do |vals|
          Hash[keys.zip(vals)]
        end
      end
    end

    def backtest(params)
      Optimization::StrategyBacktester.new(
        series: @series,
        params: params
      ).run
    rescue StandardError => e
      Rails.logger.warn("[Optimization] Backtest failed for params #{params.inspect}: #{e.message}")
      nil
    end

    def persist(best)
      return unless defined?(BestIndicatorParam)
      return unless best[:params] && best[:metrics]

      # Use upsert to update existing or create new
      # unique_by can use either column names or index name
      BestIndicatorParam.upsert(
        {
          instrument_id: @instrument.id,
          interval: @interval,
          params: best[:params],
          metrics: best[:metrics],
          score: best[:score],
          updated_at: Time.current
        },
        unique_by: [:instrument_id, :interval]
      )
    rescue StandardError => e
      Rails.logger.warn("[Optimization] Failed to persist result: #{e.message}")
    end
  end
end


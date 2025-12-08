# frozen_string_literal: true

module Optimization
  class StrategyBacktester
    def initialize(series:, params:)
      @series = series
      @params = params
      @candles = series.candles
    end

    def run
      if @candles.size < 50
        Rails.logger.warn("[StrategyBacktester] Not enough candles: #{@candles.size} < 50")
        return nil
      end

      compute_indicators!

      # Check if indicators computed successfully
      unless @rsi_values && @macd_full && @adx_values && @di_pos && @di_neg && @supertrend
        Rails.logger.warn("[StrategyBacktester] Indicators not computed successfully")
        return nil
      end

      trades = generate_trades

      if trades.empty?
        Rails.logger.warn("[StrategyBacktester] No trades generated")
        return nil
      end

      Optimization::MetricsCalculator.new(trades: trades).compute
    rescue StandardError => e
      Rails.logger.warn("[StrategyBacktester] Backtest failed: #{e.class} - #{e.message}")
      Rails.logger.warn("[StrategyBacktester] Backtrace: #{e.backtrace.first(3).join(', ')}")
      nil
    end

    private

    def compute_indicators!
      # RSI: Calculate per-index using partial series (series.rsi returns single value)
      @rsi_values = calculate_rsi_series
      Rails.logger.debug("[StrategyBacktester] RSI values: #{@rsi_values&.compact&.size || 0} non-nil")

      # MACD: Calculate per-index using partial series
      # RubyTechnicalAnalysis::Macd returns [last_macd, last_signal, last_histogram] (floats, not arrays)
      # So we need to calculate on partial series for each index
      @macd_full = calculate_macd_series
      Rails.logger.debug("[StrategyBacktester] MACD: #{@macd_full ? @macd_full[0]&.size || 0 : 'nil'} values")

      # Supertrend: Use your existing Indicators::Supertrend service
      begin
        @supertrend = Indicators::Supertrend.new(
          series: @series,
          period: @params[:st_atr] || 10,
          base_multiplier: @params[:st_mult] || 2.0
        ).call
        Rails.logger.debug("[StrategyBacktester] Supertrend: #{@supertrend[:line]&.compact&.size || 0} non-nil values")
      rescue StandardError => e
        Rails.logger.warn("[StrategyBacktester] Supertrend calculation failed: #{e.message}")
        @supertrend = nil
      end

      # ADX: Use TechnicalAnalysis gem directly on hlc format
      # Returns array of ADX objects with .adx, .plus_di (or .plusDi), .minus_di (or .minusDi)
      # ADX has warm-up period (14), so pad beginning with nil
      begin
        adx_series = TechnicalAnalysis::Adx.calculate(@series.hlc, period: 14)

        @adx_values = []
        @di_pos = []
        @di_neg = []

        adx_series.each do |row|
          @adx_values << (row.respond_to?(:adx) ? row.adx : nil)

          # TechnicalAnalysis::Adx returns objects with di_pos and di_neg methods
          plus_di = row.respond_to?(:di_pos) ? row.di_pos : nil
          minus_di = row.respond_to?(:di_neg) ? row.di_neg : nil

          @di_pos << plus_di
          @di_neg << minus_di
        end

        # Pad beginning with nil values for warm-up period
        warmup = 14
        @adx_values = Array.new(warmup, nil) + @adx_values
        @di_pos = Array.new(warmup, nil) + @di_pos
        @di_neg = Array.new(warmup, nil) + @di_neg

        Rails.logger.debug("[StrategyBacktester] ADX: #{@adx_values.compact.size} non-nil values")
      rescue StandardError => e
        Rails.logger.warn("[StrategyBacktester] ADX calculation failed: #{e.message}")
        @adx_values = []
        @di_pos = []
        @di_neg = []
      end
    end

    def calculate_rsi_series
      # RSI needs per-index calculation for accurate backtesting
      # series.rsi() returns single value, so calculate on partial series
      rsi_period = 14
      rsi_values = []
      min_period = rsi_period

      (min_period...@candles.size).each do |idx|
        partial_series = create_partial_series(idx)
        rsi_val = partial_series&.rsi(rsi_period)
        rsi_values << rsi_val
      end

      Array.new(min_period, nil) + rsi_values
    end

    def calculate_macd_series
      # MACD needs per-index calculation
      # RubyTechnicalAnalysis::Macd returns [last_macd, last_signal, last_histogram] (floats)
      fast = @params[:macd_fast] || 12
      slow = @params[:macd_slow] || 26
      signal = @params[:macd_signal] || 9
      min_period = slow + signal

      macd_line = []
      signal_line = []
      histogram_line = []

      (min_period...@candles.size).each do |idx|
        partial_series = create_partial_series(idx)
        macd_result = RubyTechnicalAnalysis::Macd.new(
          series: partial_series.closes,
          fast_period: fast,
          slow_period: slow,
          signal_period: signal
        ).call

        if macd_result && macd_result.is_a?(Array) && macd_result.size >= 3
          macd_line << macd_result[0]
          signal_line << macd_result[1]
          histogram_line << macd_result[2]
        else
          macd_line << nil
          signal_line << nil
          histogram_line << nil
        end
      end

      # Pad beginning with nil values
      [Array.new(min_period, nil) + macd_line,
       Array.new(min_period, nil) + signal_line,
       Array.new(min_period, nil) + histogram_line]
    end

    def create_partial_series(end_index)
      partial = CandleSeries.new(symbol: @series.symbol, interval: @series.interval)
      @candles[0..end_index].each { |candle| partial.add_candle(candle) }
      partial
    end

    def generate_trades
      trades = []
      position = nil
      supertrend_line = @supertrend[:line] || []
      supertrend_trends = extract_supertrend_trends

      return trades if supertrend_line.empty?

      min_lookback = [
        @params[:st_atr] || 10,
        @params[:macd_slow] || 26,
        30
      ].max

      (min_lookback...@candles.size).each do |idx|
        signal = signal_at(idx, supertrend_line, supertrend_trends)
        next unless signal

        candle = @candles[idx]
        close_price = candle.close

        if signal == :buy && position.nil?
          position = { entry: close_price, idx: idx }
        elsif signal == :sell && position
          price_move = close_price - position[:entry]
          price_move_pct = ((price_move / position[:entry]) * 100.0).round(4)

          trades << {
            entry: position[:entry],
            exit: close_price,
            entry_idx: position[:idx],
            exit_idx: idx,
            price_move: price_move,
            price_move_pct: price_move_pct
          }

          position = nil
        end
      end

      # Close any open position at end
      if position && @candles.any?
        final_price = @candles.last.close
        price_move = final_price - position[:entry]
        price_move_pct = ((price_move / position[:entry]) * 100.0).round(4)

        trades << {
          entry: position[:entry],
          exit: final_price,
          entry_idx: position[:idx],
          exit_idx: @candles.size - 1,
          price_move: price_move,
          price_move_pct: price_move_pct,
          exit_reason: 'end_of_data'
        }
      end

      trades
    end

    def extract_supertrend_trends
      # Extract trend direction for each index by comparing close to supertrend line
      supertrend_line = @supertrend[:line] || []
      trends = []

      @candles.each_with_index do |candle, idx|
        st_val = supertrend_line[idx]
        if st_val && candle.close
          trends << (candle.close >= st_val ? :bullish : :bearish)
        else
          trends << nil
        end
      end

      trends
    end

    def signal_at(idx, supertrend_line, supertrend_trends)
      return nil if idx < 30
      return nil unless @rsi_values && @macd_full && @adx_values && @di_pos && @di_neg

      rsi = @rsi_values[idx]

      # MACD arrays: @macd_full[0] = macd_array, @macd_full[1] = signal_array, @macd_full[2] = histogram_array
      # Arrays are already aligned with candle indices (padded with nil for warm-up period)
      return nil if idx >= @macd_full[0].size

      macd_line = @macd_full[0][idx]
      signal_line = @macd_full[1][idx]
      st_tr = supertrend_trends[idx]

      # ADX components
      adx = @adx_values[idx]
      di_plus = @di_pos[idx]
      di_minus = @di_neg[idx]

      return nil unless rsi && macd_line && signal_line && st_tr && adx && di_plus && di_minus

      # ---- Correct ADX logic ----
      # ADX measures trend STRENGTH (not direction)
      # DI+ vs DI- determines trend DIRECTION
      strong_trend = adx >= (@params[:adx_thresh] || 25)
      adx_up_trend = di_plus > di_minus
      adx_down_trend = di_minus > di_plus
      # ----------------------------

      # BUY = Strong trend + ADX shows upward bias (DI+ > DI-) + MACD bullish
      # RSI and Supertrend are optional filters - only check if they don't contradict
      long_condition =
        strong_trend &&
        adx_up_trend &&
        macd_line > signal_line &&
        (rsi.nil? || rsi <= 50) && # RSI not overbought
        (st_tr.nil? || st_tr == :bullish) # Supertrend optional, but if present should be bullish

      # SELL = Strong trend + ADX shows downward bias (DI- > DI+) + MACD bearish
      # RSI and Supertrend are optional filters
      short_condition =
        strong_trend &&
        adx_down_trend &&
        macd_line < signal_line &&
        (rsi.nil? || rsi >= 50) && # RSI not oversold
        (st_tr.nil? || st_tr == :bearish) # Supertrend optional, but if present should be bearish

      return :buy if long_condition
      return :sell if short_condition
      nil
    end
  end
end


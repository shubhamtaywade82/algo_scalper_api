# frozen_string_literal: true

module Optimization
  # Backtests a SINGLE indicator to measure price movement after signals
  class SingleIndicatorBacktester
    def initialize(series:, indicator:, params:)
      @series = series
      @indicator = indicator.to_sym
      @params = params
      @candles = series.candles
    end

    def run
      return nil if @candles.size < 50

      signals = generate_signals
      return nil if signals.empty?

      # Measure price movement after each signal
      price_movements = measure_price_movements(signals)

      return nil if price_movements.empty?

      calculate_metrics(signals, price_movements)
    rescue StandardError => e
      Rails.logger.warn("[SingleIndicatorBacktester] Backtest failed: #{e.class} - #{e.message}")
      nil
    end

    private

    def generate_signals
      signals = []

      case @indicator
      when :adx
        signals = generate_adx_signals
      when :supertrend
        signals = generate_supertrend_signals
      when :macd
        signals = generate_macd_signals
      when :atr
        signals = generate_atr_signals
      when :rsi
        signals = generate_rsi_signals
      end

      signals
    end

    def generate_adx_signals
      signals = []
      period = @params[:period] || 14
      threshold = @params[:threshold] || 20

      # Calculate ADX series
      adx_series = TechnicalAnalysis::Adx.calculate(@series.hlc, period: period)
      return [] if adx_series.empty?

      adx_values = []
      di_pos = []
      di_neg = []

      adx_series.each do |row|
        adx_values << row.adx
        di_pos << row.di_pos
        di_neg << row.di_neg
      end

      # Pad for warm-up period
      warmup = period
      adx_values = Array.new(warmup, nil) + adx_values
      di_pos = Array.new(warmup, nil) + di_pos
      di_neg = Array.new(warmup, nil) + di_neg

      # Generate signals
      (warmup...@candles.size).each do |idx|
        next unless adx_values[idx] && di_pos[idx] && di_neg[idx]

        adx = adx_values[idx]
        di_plus = di_pos[idx]
        di_minus = di_neg[idx]

        # Strong trend with upward bias
        if adx >= threshold && di_plus > di_minus
          signals << { type: :buy, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        # Strong trend with downward bias
        elsif adx >= threshold && di_minus > di_plus
          signals << { type: :sell, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        end
      end

      signals
    end

    def generate_atr_signals
      signals = []
      period = @params[:period] || 14

      # Calculate ATR values for the series
      atr_values = []
      (period...@candles.size).each do |idx|
        partial_series = create_partial_series(idx)
        atr_val = partial_series&.atr(period)
        atr_values << atr_val
      end

      atr_values = Array.new(period, nil) + atr_values

      # Calculate ATR moving average for trend detection
      atr_ma_period = [period / 2, 5].max
      atr_ma = []
      (period + atr_ma_period...@candles.size).each do |idx|
        recent_atrs = atr_values[(idx - atr_ma_period + 1)..idx].compact
        next if recent_atrs.empty?

        avg_atr = recent_atrs.sum / recent_atrs.size.to_f
        atr_ma << avg_atr
      end

      atr_ma = Array.new(period + atr_ma_period, nil) + atr_ma

      # Generate signals based on ATR volatility patterns
      # Signal when ATR is increasing (volatility expansion) - potential breakout
      (period + atr_ma_period...@candles.size).each do |idx|
        current_atr = atr_values[idx]
        prev_atr = atr_values[idx - 1]
        avg_atr = atr_ma[idx]

        next unless current_atr && prev_atr && avg_atr

        # Buy signal: ATR increasing above average (volatility expansion, potential upward move)
        if current_atr > prev_atr && current_atr > avg_atr * 1.1
          signals << { type: :buy, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        # Sell signal: ATR decreasing below average (volatility compression, potential downward move)
        elsif current_atr < prev_atr && current_atr < avg_atr * 0.9
          signals << { type: :sell, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        end
      end

      signals
    end

    def generate_rsi_signals
      signals = []
      period = @params[:period] || 14
      oversold = @params[:oversold] || 30
      overbought = @params[:overbought] || 70

      # Calculate RSI per-index
      rsi_values = []
      (period...@candles.size).each do |idx|
        partial_series = create_partial_series(idx)
        rsi_val = partial_series&.rsi(period)
        rsi_values << rsi_val
      end

      rsi_values = Array.new(period, nil) + rsi_values

      # Generate signals
      (period...@candles.size).each do |idx|
        rsi = rsi_values[idx]
        next unless rsi

        if rsi <= oversold
          signals << { type: :buy, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        elsif rsi >= overbought
          signals << { type: :sell, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        end
      end

      signals
    end

    def generate_macd_signals
      signals = []
      fast = @params[:fast] || 12
      slow = @params[:slow] || 26
      signal_period = @params[:signal] || 9
      min_period = slow + signal_period

      # Calculate MACD per-index
      macd_line = []
      signal_line = []

      (min_period...@candles.size).each do |idx|
        partial_series = create_partial_series(idx)
        macd_result = RubyTechnicalAnalysis::Macd.new(
          series: partial_series.closes,
          fast_period: fast,
          slow_period: slow,
          signal_period: signal_period
        ).call

        if macd_result && macd_result.is_a?(Array) && macd_result.size >= 3
          macd_line << macd_result[0]
          signal_line << macd_result[1]
        else
          macd_line << nil
          signal_line << nil
        end
      end

      macd_line = Array.new(min_period, nil) + macd_line
      signal_line = Array.new(min_period, nil) + signal_line

      # Generate signals
      (min_period...@candles.size).each do |idx|
        macd = macd_line[idx]
        sig = signal_line[idx]
        next unless macd && sig

        if macd > sig
          signals << { type: :buy, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        elsif macd < sig
          signals << { type: :sell, index: idx, price: @candles[idx].close, timestamp: @candles[idx].timestamp }
        end
      end

      signals
    end

    def generate_supertrend_signals
      signals = []
      atr_period = @params[:atr_period] || 10
      multiplier = @params[:multiplier] || 2.0

      # Calculate Supertrend
      supertrend = Indicators::Supertrend.new(
        series: @series,
        period: atr_period,
        base_multiplier: multiplier
      ).call

      supertrend_line = supertrend[:line] || []
      return [] if supertrend_line.empty?

      # Generate signals based on Supertrend
      @candles.each_with_index do |candle, idx|
        st_val = supertrend_line[idx]
        next unless st_val

        if candle.close > st_val
          signals << { type: :buy, index: idx, price: candle.close, timestamp: candle.timestamp }
        elsif candle.close < st_val
          signals << { type: :sell, index: idx, price: candle.close, timestamp: candle.timestamp }
        end
      end

      signals
    end

    def measure_price_movements(signals)
      movements = []

      signals.each do |signal|
        entry_idx = signal[:index]
        entry_price = signal[:price]
        signal_type = signal[:type]

        # Look ahead to find maximum price movement
        max_move = 0
        max_move_pct = 0

        # Check next 20 candles (or until end of data)
        lookahead = [20, @candles.size - entry_idx - 1].min

        (1..lookahead).each do |offset|
          next_idx = entry_idx + offset
          break if next_idx >= @candles.size

          candle = @candles[next_idx]

          if signal_type == :buy
            # For buy: measure upward movement
            move = candle.high - entry_price
            move_pct = ((move / entry_price) * 100.0).round(4)
          else
            # For sell: measure downward movement
            move = entry_price - candle.low
            move_pct = ((move / entry_price) * 100.0).round(4)
          end

          if move_pct > max_move_pct
            max_move = move
            max_move_pct = move_pct
          end
        end

        movements << {
          signal: signal,
          max_move: max_move,
          max_move_pct: max_move_pct,
          lookahead_candles: lookahead
        }
      end

      movements
    end

    def calculate_metrics(signals, price_movements)
      return nil if price_movements.empty?

      movements_pct = price_movements.map { |m| m[:max_move_pct] }
      avg_move = movements_pct.sum / movements_pct.size.to_f

      # Count wins (positive movement)
      wins = movements_pct.select { |m| m > 0 }
      win_rate = wins.size.to_f / movements_pct.size

      # Average win
      avg_win = wins.any? ? (wins.sum / wins.size.to_f) : 0.0

      # Max movement
      max_move = movements_pct.max || 0.0

      {
        total_signals: signals.size,
        avg_price_move: avg_move,
        avg_price_move_pct: avg_move,
        win_rate: win_rate,
        avg_win_pct: avg_win,
        max_move_pct: max_move,
        total_movements: price_movements.size
      }
    end

    def create_partial_series(end_index)
      partial = CandleSeries.new(symbol: @series.symbol, interval: @series.interval)
      @candles[0..end_index].each { |candle| partial.add_candle(candle) }
      partial
    end
  end
end

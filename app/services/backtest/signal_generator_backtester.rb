# frozen_string_literal: true

module Backtest
  # Backtests the Signal Generator (Supertrend + ADX) to measure signal quality
  # Tests signal accuracy, distribution, and forward-looking price movement
  class SignalGeneratorBacktester
    attr_reader :instrument, :interval_1m, :interval_5m, :days_back, :results, :signal_stats

    def initialize(symbol:, interval_1m: '1', interval_5m: '5', days_back: 30, supertrend_cfg: {}, adx_min_strength: 0)
      @interval_1m = interval_1m
      @interval_5m = interval_5m
      @days_back = days_back
      # supertrend_cfg should always be provided (from OptimizedParamsLoader or defaults)
      @supertrend_cfg = supertrend_cfg.presence || { period: 7, base_multiplier: 3.0 }
      @adx_min_strength = adx_min_strength || 0
      @results = []
      @signal_stats = {
        total_signals: 0,
        bullish_signals: 0,
        bearish_signals: 0,
        signals_with_price_moves: 0,
        profitable_signals: 0,
        losing_signals: 0
      }

      @instrument = Instrument.segment_index.find_by(symbol_name: symbol)
      unless @instrument
        raise "Instrument #{symbol} not found"
      end

      Rails.logger.info("[SignalBacktest] Initialized backtest for #{symbol}")
    end

    def self.run(symbol:, interval_1m: '1', interval_5m: '5', days_back: 30, supertrend_cfg: nil, adx_min_strength: nil)
      # Load instrument first to check for optimized parameters
      instrument = Instrument.segment_index.find_by(symbol_name: symbol)
      raise "Instrument #{symbol} not found" unless instrument

      # Load optimized parameters (or use provided overrides, or defaults)
      # Use interval_5m for optimization lookup (signals are generated on 5m)
      optimized = Backtest::OptimizedParamsLoader.load_for_backtest(
        instrument: instrument,
        interval: interval_5m,
        supertrend_cfg: supertrend_cfg,
        adx_min_strength: adx_min_strength
      )

      if optimized[:source] == :optimized
        $stdout.puts "[SignalBacktest] Using optimized parameters (Score: #{optimized[:score]&.round(3)})"
        $stdout.flush
      elsif optimized[:source] == :manual
        $stdout.puts "[SignalBacktest] Using manual override parameters"
        $stdout.flush
      else
        $stdout.puts "[SignalBacktest] Using default parameters (no optimization found)"
        $stdout.flush
      end

      service = new(
        symbol: symbol,
        interval_1m: interval_1m,
        interval_5m: interval_5m,
        days_back: days_back,
        supertrend_cfg: optimized[:supertrend_cfg],
        adx_min_strength: optimized[:adx_min_strength]
      )
      service.execute
      service
    end

    def execute
      Rails.logger.info("[SignalBacktest] Starting signal generator backtest for #{instrument.symbol_name}")
      $stdout.puts "[SignalBacktest] Starting backtest for #{instrument.symbol_name}..."
      $stdout.flush

      # Fetch historical OHLC data for both timeframes
      $stdout.puts "[SignalBacktest] Fetching #{interval_1m}m OHLC data from API..."
      $stdout.flush
      bars_1m = fetch_ohlc_data(interval_1m)

      $stdout.puts "[SignalBacktest] Fetching #{interval_5m}m OHLC data from API..."
      $stdout.flush
      bars_5m = fetch_ohlc_data(interval_5m)

      if bars_1m.blank? || bars_5m.blank?
        error_msg = "No OHLC data available - 1m: #{bars_1m.present? ? 'OK' : 'MISSING'}, 5m: #{bars_5m.present? ? 'OK' : 'MISSING'}"
        Rails.logger.error("[SignalBacktest] #{error_msg}")
        $stdout.puts "[SignalBacktest] ❌ #{error_msg}"
        $stdout.flush
        return { error: error_msg }
      end

      # Build candle series
      $stdout.puts "[SignalBacktest] Building candle series..."
      $stdout.flush
      series_1m = build_candle_series(bars_1m, interval_1m)
      series_5m = build_candle_series(bars_5m, interval_5m)

      if series_1m.candles.empty? || series_5m.candles.empty?
        error_msg = "Failed to build candle series - 1m: #{series_1m.candles.size}, 5m: #{series_5m.candles.size}"
        Rails.logger.error("[SignalBacktest] #{error_msg}")
        $stdout.puts "[SignalBacktest] ❌ #{error_msg}"
        $stdout.flush
        return { error: error_msg }
      end

      $stdout.puts "[SignalBacktest] ✅ Built series: 1m=#{series_1m.candles.size}, 5m=#{series_5m.candles.size}"
      $stdout.puts "[SignalBacktest] Analyzing signals..."
      $stdout.flush

      # Analyze signals
      analyze_signals(series_1m, series_5m)

      Rails.logger.info("[SignalBacktest] Completed: #{@signal_stats[:total_signals]} signals analyzed")
      $stdout.puts "[SignalBacktest] ✅ Completed: #{@signal_stats[:total_signals]} signals analyzed"
      $stdout.flush

      self
    end

    def summary
      return {} if @results.empty?

      total = @signal_stats[:total_signals]
      bullish = @signal_stats[:bullish_signals]
      bearish = @signal_stats[:bearish_signals]
      profitable = @signal_stats[:profitable_signals]
      losing = @signal_stats[:losing_signals]

      # Calculate price movement statistics
      price_movements = @results.map { |r| r[:price_move_pct] }.compact
      avg_move = price_movements.any? ? (price_movements.sum / price_movements.size) : 0
      max_move = price_movements.any? ? price_movements.max : 0
      min_move = price_movements.any? ? price_movements.min : 0

      {
        total_signals: total,
        bullish_signals: bullish,
        bearish_signals: bearish,
        bullish_pct: total.positive? ? (bullish.to_f / total * 100).round(2) : 0,
        bearish_pct: total.positive? ? (bearish.to_f / total * 100).round(2) : 0,
        profitable_signals: profitable,
        losing_signals: losing,
        accuracy_pct: total.positive? ? (profitable.to_f / total * 100).round(2) : 0,
        avg_price_move_pct: avg_move.round(2),
        max_price_move_pct: max_move.round(2),
        min_price_move_pct: min_move.round(2),
        signals_with_moves: @signal_stats[:signals_with_price_moves],
        signals_with_moves_pct: total.positive? ? (@signal_stats[:signals_with_price_moves].to_f / total * 100).round(2) : 0
      }
    end

    def print_summary
      s = summary
      return if s.empty?

      divider = '=' * 80
      puts "\n#{divider}"
      puts 'SIGNAL GENERATOR BACKTEST SUMMARY'
      puts divider
      puts "Supertrend: period=#{@supertrend_cfg[:period]}, multiplier=#{@supertrend_cfg[:base_multiplier]}"
      puts "ADX Min Strength: #{@adx_min_strength}"
      puts divider
      puts "Total Signals:        #{s[:total_signals]}"
      puts "Bullish Signals:      #{s[:bullish_signals]} (#{s[:bullish_pct]}%)"
      puts "Bearish Signals:      #{s[:bearish_signals]} (#{s[:bearish_pct]}%)"
      puts divider
      puts "Profitable Signals:   #{s[:profitable_signals]}"
      puts "Losing Signals:       #{s[:losing_signals]}"
      puts "Accuracy:             #{s[:accuracy_pct]}%"
      puts divider
      puts "Avg Price Move:       #{s[:avg_price_move_pct]}%"
      puts "Max Price Move:       #{s[:max_price_move_pct]}%"
      puts "Min Price Move:       #{s[:min_price_move_pct]}%"
      puts "Signals with Moves:   #{s[:signals_with_moves]} (#{s[:signals_with_moves_pct]}%)"
      puts divider
    end

    private

    def fetch_ohlc_data(interval)
      to_date = Date.today - 1.day
      from_date = to_date - @days_back.days

      Rails.logger.info("[SignalBacktest] Fetching #{interval}m OHLC from API: #{from_date} to #{to_date}")
      $stdout.puts "[SignalBacktest]   Fetching #{interval}m data from API: #{from_date} to #{to_date}..."
      $stdout.flush

      start_time = Time.current
      data = @instrument.intraday_ohlc(
        interval: interval,
        from_date: from_date.to_s,
        to_date: to_date.to_s,
        days: @days_back
      )
      elapsed = Time.current - start_time

      if data.present?
        size = data.is_a?(Hash) && data['high'].is_a?(Array) ? data['high'].size : (data.is_a?(Array) ? data.size : data.keys.size)
        Rails.logger.info("[SignalBacktest] Fetched #{interval}m OHLC: #{size} records in #{elapsed.round(2)}s")
        $stdout.puts "[SignalBacktest]   ✅ Fetched #{size} records in #{elapsed.round(2)}s"
        $stdout.flush
      else
        Rails.logger.warn("[SignalBacktest] No data returned for #{interval}m OHLC")
        $stdout.puts "[SignalBacktest]   ⚠️  No data returned"
        $stdout.flush
      end

      data
    rescue StandardError => e
      Rails.logger.error("[SignalBacktest] Failed to fetch OHLC (#{interval}m): #{e.class} - #{e.message}")
      $stdout.puts "[SignalBacktest]   ❌ Error: #{e.class} - #{e.message}"
      $stdout.flush
      nil
    end

    def build_candle_series(ohlc_data, interval)
      series = CandleSeries.new(symbol: @instrument.symbol_name, interval: interval)
      series.load_from_raw(ohlc_data)
      series
    end

    def analyze_signals(series_1m, series_5m)
      last_5m_index = 0
      i = 0
      total_candles = series_1m.candles.size

      while i < total_candles
        candle_1m = series_1m.candles[i]
        current_time = candle_1m.timestamp

        # Skip if outside trading hours
        unless trading_hours?(current_time)
          i += 1
          next
        end

        # Generate signal
        signal_result = generate_signal(series_1m, series_5m, i, current_time, last_5m_index)
        last_5m_index = signal_result[:last_5m_index] if signal_result && signal_result[:last_5m_index]

        if signal_result && signal_result[:signal]
          @signal_stats[:total_signals] += 1
          @signal_stats[:bullish_signals] += 1 if signal_result[:direction] == :bullish
          @signal_stats[:bearish_signals] += 1 if signal_result[:direction] == :bearish

          # Measure price movement after signal (next 10 candles or until end)
          price_move = measure_price_movement(series_1m, i, signal_result[:direction])
          if price_move
            @signal_stats[:signals_with_price_moves] += 1
            @signal_stats[:profitable_signals] += 1 if price_move[:profitable]
            @signal_stats[:losing_signals] += 1 unless price_move[:profitable]

            @results << {
              timestamp: current_time,
              direction: signal_result[:direction],
              confidence: signal_result[:confidence],
              adx_value: signal_result[:adx_value],
              price_move_pct: price_move[:move_pct],
              profitable: price_move[:profitable],
              candles_analyzed: price_move[:candles]
            }
          end
        end

        i += 1
      end
    end

    def generate_signal(series_1m, series_5m, index, current_time, last_5m_index = 0)
      # Find corresponding 5m candle
      candle_5m_index = find_5m_candle_index(series_5m, current_time, start_from: last_5m_index)
      return { signal: nil, direction: nil } if candle_5m_index.nil?

      # ADX needs at least 2*period candles (typically 2*14 = 28) for accurate calculation
      # Supertrend needs at least period candles
      min_required = [@supertrend_cfg[:period] || 7, 28].max
      return { signal: nil, direction: nil } if candle_5m_index < min_required

      # Build series up to current index for Supertrend
      temp_series_5m = CandleSeries.new(symbol: 'temp', interval: '5')
      series_5m.candles[0..candle_5m_index].each { |c| temp_series_5m.add_candle(c) }

      # Calculate Supertrend on 5m
      st_cfg = @supertrend_cfg.dup
      st_cfg[:base_multiplier] = st_cfg.delete(:multiplier) if st_cfg.key?(:multiplier)
      st_service = Indicators::Supertrend.new(series: temp_series_5m, **st_cfg)
      st_result = st_service.call

      # Calculate ADX on 5m
      adx_value = calculate_adx_for_series(series_5m, candle_5m_index)

      # Apply ADX filter if enabled
      if @adx_min_strength.positive? && adx_value < @adx_min_strength
        return { signal: nil, direction: nil }
      end

      # Determine direction
      return { signal: nil, direction: nil } if st_result.blank? || st_result[:trend].nil?

      direction = case st_result[:trend]
                  when :bullish
                    :bullish
                  when :bearish
                    :bearish
                  else
                    return { signal: nil, direction: nil }
                  end

      confidence = calculate_confidence(st_result, adx_value)

      {
        signal: { type: direction == :bullish ? :ce : :pe, confidence: confidence },
        direction: direction,
        supertrend: st_result,
        adx_value: adx_value,
        last_5m_index: candle_5m_index
      }
    rescue StandardError => e
      Rails.logger.error("[SignalBacktest] Error generating signal: #{e.class} - #{e.message}")
      { signal: nil, direction: nil }
    end

    def measure_price_movement(series, signal_index, direction)
      # Measure price movement in the next 10 candles (or until end)
      lookahead = 10
      end_index = [signal_index + lookahead, series.candles.size - 1].min
      return nil if signal_index >= series.candles.size - 1

      signal_candle = series.candles[signal_index]
      end_candle = series.candles[end_index]
      signal_price = signal_candle.close
      end_price = end_candle.close

      return nil unless signal_price&.positive? && end_price&.positive?

      move_pct = if direction == :bullish
                   ((end_price - signal_price) / signal_price * 100)
                 else
                   ((signal_price - end_price) / signal_price * 100)
                 end

      {
        move_pct: move_pct.round(2),
        profitable: move_pct > 0,
        candles: end_index - signal_index
      }
    end

    def calculate_adx_for_series(series, index)
      # ADX needs at least 2*period candles for accurate calculation (2*14 = 28)
      # Plus 1 for the TechnicalAnalysis gem requirement
      min_required = 29
      return 0 if index < min_required - 1

      recent_candles = series.candles[0..index]
      return 0 if recent_candles.size < min_required

      temp_series = CandleSeries.new(symbol: 'temp', interval: '5')
      recent_candles.each { |c| temp_series.add_candle(c) }

      # Only calculate if we have enough candles
      return 0 if temp_series.candles.size < min_required

      temp_series.adx(14) || 0
    rescue StandardError => e
      # Suppress "Not enough data" errors - they're expected for early candles
      unless e.message.to_s.include?('Not enough data')
        Rails.logger.error("[SignalBacktest] ADX calculation error: #{e.class} - #{e.message}")
      end
      0
    end

    def calculate_confidence(st_result, adx_value)
      confidence = 50 # Base

      # Add confidence for strong ADX
      confidence += 10 if adx_value >= 25
      confidence += 5 if adx_value >= 20

      # Add confidence for clear trend
      confidence += 10 if st_result[:trend] == :bullish || st_result[:trend] == :bearish

      [confidence, 100].min
    end

    def find_5m_candle_index(series_5m, target_time, start_from: 0)
      candles = series_5m.candles
      return nil if candles.empty?

      start_idx = [[start_from, 0].max, candles.size - 1].min

      # Forward search from cached position
      max_search = [candles.size - start_idx, 10].min
      (start_idx...[start_idx + max_search, candles.size].min).each do |idx|
        candle = candles[idx]
        next_candle = candles[idx + 1] if idx + 1 < candles.size

        if candle.timestamp <= target_time
          if idx == candles.size - 1 || next_candle.nil? || next_candle.timestamp > target_time
            return idx
          end
        else
          break
        end
      end

      # Fallback: full search
      candles.each_with_index do |candle, idx|
        next_candle = candles[idx + 1] if idx + 1 < candles.size
        if candle.timestamp <= target_time && (idx == candles.size - 1 || next_candle.nil? || next_candle.timestamp > target_time)
          return idx
        end
      end

      nil
    end

    def trading_hours?(time)
      time_str = time.strftime('%H:%M')
      time_str >= '09:15' && time_str <= '15:15'
    end
  end
end


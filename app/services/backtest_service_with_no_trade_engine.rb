# frozen_string_literal: true

# Backtest Service with No-Trade Engine Integration
# Backtests Supertrend + ADX strategy with No-Trade Engine validation on historical index data
#
# Usage:
#   service = BacktestServiceWithNoTradeEngine.run(
#     symbol: 'NIFTY',
#     interval_1m: '1',
#     interval_5m: '5',
#     days_back: 90,
#     supertrend_cfg: { period: 7, multiplier: 3.0 },
#     adx_min_strength: 0
#   )
#   service.print_summary
#
# Features:
# - Phase 1: Quick No-Trade pre-check (time windows, basic volatility)
# - Signal Generation: Supertrend + ADX on 5m timeframe
# - Phase 2: Detailed No-Trade validation (all 11 conditions)
# - Position Management: SL/TP/trailing/time-based exits
# - Performance Metrics: Win rate, expectancy, No-Trade Engine stats
class BacktestServiceWithNoTradeEngine
  attr_reader :instrument, :interval_1m, :interval_5m, :days_back, :results, :no_trade_stats

  def initialize(symbol:, interval_1m: '1', interval_5m: '5', days_back: 90, supertrend_cfg: {}, adx_min_strength: 0)
    @interval_1m = interval_1m
    @interval_5m = interval_5m
    @days_back = days_back
    @supertrend_cfg = supertrend_cfg || { period: 7, multiplier: 3.0 }
    @adx_min_strength = adx_min_strength
    @results = []
    @no_trade_stats = {
      phase1_blocked: 0,
      phase2_blocked: 0,
      signal_generated: 0,
      trades_executed: 0,
      phase1_reasons: Hash.new(0),
      phase2_reasons: Hash.new(0)
    }

    @instrument = Instrument.segment_index.find_by(symbol_name: symbol)
    unless @instrument
      raise "Instrument #{symbol} not found"
    end

    Rails.logger.info("[Backtest] Initialized backtest for #{symbol} with No-Trade Engine")
  end

  def self.run(symbol:, interval_1m: '1', interval_5m: '5', days_back: 90, supertrend_cfg: {}, adx_min_strength: 0)
    service = new(
      symbol: symbol,
      interval_1m: interval_1m,
      interval_5m: interval_5m,
      days_back: days_back,
      supertrend_cfg: supertrend_cfg,
      adx_min_strength: adx_min_strength
    )
    service.execute
    service
  end

  def execute
    Rails.logger.info("[Backtest] Starting backtest with No-Trade Engine for #{instrument.symbol_name}")

    # Fetch historical OHLC data for both timeframes
    bars_1m = fetch_ohlc_data(interval_1m)
    bars_5m = fetch_ohlc_data(interval_5m)

    return { error: 'No OHLC data available' } if bars_1m.blank? || bars_5m.blank?

    Rails.logger.info("[Backtest] Loaded #{bars_1m.size} 1m candles and #{bars_5m.size} 5m candles")

    # Build candle series
    series_1m = build_candle_series(bars_1m, interval_1m)
    series_5m = build_candle_series(bars_5m, interval_5m)

    return { error: 'Failed to build candle series' } if series_1m.candles.empty? || series_5m.candles.empty?

    # Simulate trading with No-Trade Engine validation
    simulate_trading_with_no_trade_engine(series_1m, series_5m)

    Rails.logger.info("[Backtest] Completed: #{@results.size} trades executed")
    Rails.logger.info("[Backtest] No-Trade Stats: Phase1 blocked=#{@no_trade_stats[:phase1_blocked]}, Phase2 blocked=#{@no_trade_stats[:phase2_blocked]}, Signals=#{@no_trade_stats[:signal_generated]}, Trades=#{@no_trade_stats[:trades_executed]}")

    self
  end

  def summary
    return {} if @results.empty?

    wins = @results.select { |r| r[:pnl_percent] > 0 }
    losses = @results.select { |r| r[:pnl_percent] <= 0 }
    trade_count = @results.size
    win_total_percent = wins.sum { |w| w[:pnl_percent] }
    loss_total_percent = losses.sum { |l| l[:pnl_percent] }
    total_pnl_percent = @results.sum { |r| r[:pnl_percent] }

    {
      total_trades: trade_count,
      winning_trades: wins.size,
      losing_trades: losses.size,
      win_rate: (wins.size.to_f / trade_count * 100).round(2),
      avg_win_percent: wins.any? ? (win_total_percent / wins.size.to_f).round(2) : 0,
      avg_loss_percent: losses.any? ? (loss_total_percent / losses.size.to_f).round(2) : 0,
      total_pnl_percent: total_pnl_percent.round(2),
      expectancy: (total_pnl_percent / trade_count.to_f).round(2),
      max_win: wins.any? ? wins.max_by { |w| w[:pnl_percent] }[:pnl_percent].round(2) : 0,
      max_loss: losses.any? ? losses.min_by { |l| l[:pnl_percent] }[:pnl_percent].round(2) : 0,
      no_trade_stats: @no_trade_stats,
      trades: @results
    }
  end

  def print_summary
    s = summary
    return puts 'No trades executed' if s.empty?

    separator = '=' * 80
    divider = '-' * 80

    puts "\n#{separator}"
    puts "BACKTEST RESULTS: #{instrument.symbol_name} (WITH NO-TRADE ENGINE)"
    puts separator
    puts "Period: Last #{days_back} days | Intervals: #{interval_1m}m (signal), #{interval_5m}m (ADX)"
    puts divider
    puts "Total Trades:      #{s[:total_trades]}"
    puts "Winning Trades:    #{s[:winning_trades]} (#{s[:win_rate]}%)"
    puts "Losing Trades:     #{s[:losing_trades]}"
    puts divider
    puts "Avg Win:           +#{s[:avg_win_percent]}%"
    puts "Avg Loss:          #{s[:avg_loss_percent]}%"
    puts "Max Win:           +#{s[:max_win]}%"
    puts "Max Loss:          #{s[:max_loss]}%"
    puts divider
    puts "Total P&L:         #{'+' if s[:total_pnl_percent] > 0}#{s[:total_pnl_percent]}%"
    puts "Expectancy:        #{'+' if s[:expectancy] > 0}#{s[:expectancy]}% per trade"
    puts divider
    puts "NO-TRADE ENGINE STATS:"
    puts "  Phase 1 Blocked:  #{s[:no_trade_stats][:phase1_blocked]}"
    puts "  Phase 2 Blocked:  #{s[:no_trade_stats][:phase2_blocked]}"
    puts "  Signals Generated: #{s[:no_trade_stats][:signal_generated]}"
    puts "  Trades Executed:  #{s[:no_trade_stats][:trades_executed]}"
    block_rate = calculate_block_rate(s[:no_trade_stats])
    puts "  Block Rate:       #{block_rate}%"
    puts divider
    puts "Top Phase 1 Block Reasons:"
    s[:no_trade_stats][:phase1_reasons].sort_by { |_k, v| -v }.first(5).each do |reason, count|
      puts "  #{reason}: #{count}"
    end
    puts "Top Phase 2 Block Reasons:"
    s[:no_trade_stats][:phase2_reasons].sort_by { |_k, v| -v }.first(5).each do |reason, count|
      puts "  #{reason}: #{count}"
    end
    puts "#{separator}\n"
  end

  private

  def fetch_ohlc_data(interval)
    to_date = Date.today - 1.day
    from_date = to_date - @days_back.days

    @instrument.intraday_ohlc(
      interval: interval,
      from_date: from_date.to_s,
      to_date: to_date.to_s,
      days: @days_back
    )
  rescue StandardError => e
    Rails.logger.error("[Backtest] Failed to fetch OHLC (#{interval}m): #{e.message}")
    nil
  end

  def build_candle_series(ohlc_data, interval)
    series = CandleSeries.new(symbol: @instrument.symbol_name, interval: interval)
    series.load_from_raw(ohlc_data)
    series
  end

  def simulate_trading_with_no_trade_engine(series_1m, series_5m)
    open_position = nil
    i = 0

    # Process 1m candles (for signal generation)
    while i < series_1m.candles.size
      candle_1m = series_1m.candles[i]
      current_time = candle_1m.timestamp

      # Skip if outside trading hours (9:15 AM - 3:15 PM IST)
      next unless trading_hours?(current_time)

      # Check exit conditions if position is open
      if open_position
        exit_result = check_exit(open_position, candle_1m, i, series_1m)
        if exit_result
          @results << exit_result
          open_position = nil
        end
      end

      # Try to enter new position if none is open
      if open_position.nil?
        # Phase 1: Quick No-Trade pre-check
        phase1_result = quick_no_trade_precheck_historical(
          candle_1m: candle_1m,
          series_1m: series_1m,
          index: i,
          current_time: current_time
        )

        unless phase1_result[:allowed]
          @no_trade_stats[:phase1_blocked] += 1
          phase1_result[:reasons].each { |r| @no_trade_stats[:phase1_reasons][r] += 1 }
          i += 1
          next
        end

        # Generate Supertrend + ADX signal
        signal_result = generate_supertrend_adx_signal(series_1m, series_5m, i, current_time)

        unless signal_result[:signal]
          i += 1
          next
        end

        @no_trade_stats[:signal_generated] += 1

        # Phase 2: Detailed No-Trade validation
        phase2_result = validate_no_trade_conditions_historical(
          signal_direction: signal_result[:direction],
          candle_1m: candle_1m,
          series_1m: series_1m,
          series_5m: series_5m,
          index: i,
          current_time: current_time
        )

        unless phase2_result[:allowed]
          @no_trade_stats[:phase2_blocked] += 1
          phase2_result[:reasons].each { |r| @no_trade_stats[:phase2_reasons][r] += 1 }
          i += 1
          next
        end

        # Enter position
        open_position = enter_position(signal_result, candle_1m, i)
        @no_trade_stats[:trades_executed] += 1 if open_position
      end

      i += 1
    end

    # Force exit any open position at end
    if open_position
      last_candle = series_1m.candles.last
      exit_result = force_exit(open_position, last_candle, series_1m.candles.size - 1, 'end_of_data')
      @results << exit_result
    end
  end

  def quick_no_trade_precheck_historical(candle_1m:, series_1m:, index:, current_time:)
    reasons = []
    score = 0

    # Time windows
    time_str = current_time.strftime('%H:%M')
    if time_str >= '09:15' && time_str <= '09:18'
      reasons << 'Avoid first 3 minutes'
      score += 1
    end

    if time_str >= '11:20' && time_str <= '13:30'
      reasons << 'Lunch-time theta zone'
      score += 1
    end

    if time_str > '15:05'
      reasons << 'Post 3:05 PM - theta crush'
      score += 1
    end

    # Basic volatility check (last 10 candles)
    if index >= 10
      recent_bars = series_1m.candles[(index - 9)..index]
      range_pct = Entries::RangeUtils.range_pct(recent_bars)
      if range_pct < 0.1
        reasons << 'Low volatility: 10m range < 0.1%'
        score += 1
      end
    end

    # Basic option chain check (simulated - use historical IV if available)
    # For backtesting, we'll skip IV/spread checks as historical option data may not be available
    # In production, these would be checked

    {
      allowed: score < 3,
      score: score,
      reasons: reasons
    }
  end

  def generate_supertrend_adx_signal(series_1m, series_5m, index, current_time)
    # Use 5m timeframe for Supertrend + ADX (as per production)
    # Find corresponding 5m candle
    candle_5m_index = find_5m_candle_index(series_5m, current_time)
    return { signal: nil, direction: nil } if candle_5m_index.nil? || candle_5m_index < 14

    # Need enough candles for Supertrend calculation
    return { signal: nil, direction: nil } if candle_5m_index < @supertrend_cfg[:period] || candle_5m_index < 14

    # Build series up to current index for Supertrend
    temp_series_5m = CandleSeries.new(symbol: 'temp', interval: '5')
    series_5m.candles[0..candle_5m_index].each { |c| temp_series_5m.add_candle(c) }

    # Calculate Supertrend on 5m
    st_service = Indicators::Supertrend.new(series: temp_series_5m, **@supertrend_cfg)
    st_result = st_service.call

    # Calculate ADX on 5m
    adx_value = calculate_adx_for_series(series_5m, candle_5m_index)

    # Determine direction
    direction = decide_direction_from_supertrend_adx(st_result, adx_value, candle_5m_index)

    return { signal: nil, direction: nil } if direction == :avoid

    {
      signal: { type: direction == :bullish ? :ce : :pe, confidence: calculate_confidence(st_result, adx_value) },
      direction: direction,
      supertrend: st_result,
      adx_value: adx_value
    }
  end

  def validate_no_trade_conditions_historical(signal_direction:, candle_1m:, series_1m:, series_5m:, index:, current_time:)
    # Build context for No-Trade Engine
    # Get recent bars for context building
    bars_1m_recent = index >= 20 ? series_1m.candles[(index - 19)..index] : series_1m.candles[0..index]
    bars_5m_recent = get_recent_5m_bars(series_5m, current_time, 20)

    return { allowed: true, score: 0, reasons: [] } if bars_1m_recent.size < 10 || bars_5m_recent.size < 15

    # Build context (simplified for historical data - no option chain)
    ctx = build_no_trade_context_historical(
      bars_1m: bars_1m_recent,
      bars_5m: bars_5m_recent,
      current_time: current_time
    )

    # Validate with No-Trade Engine
    result = Entries::NoTradeEngine.validate(ctx)

    {
      allowed: result.allowed,
      score: result.score,
      reasons: result.reasons
    }
  end

  def build_no_trade_context_historical(bars_1m:, bars_5m:, current_time:)
    # Calculate ADX/DI from 5m bars
    adx_data = calculate_adx_data_from_bars(bars_5m)

    # Build simplified context (without option chain data)
    OpenStruct.new(
      # Trend indicators
      adx_5m: adx_data[:adx] || 0,
      plus_di_5m: adx_data[:plus_di] || 0,
      minus_di_5m: adx_data[:minus_di] || 0,

      # Structure indicators
      bos_present: Entries::StructureDetector.bos?(bars_1m),
      in_opposite_ob: Entries::StructureDetector.inside_opposite_ob?(bars_1m),
      inside_fvg: Entries::StructureDetector.inside_fvg?(bars_1m),

      # VWAP indicators
      near_vwap: Entries::VWAPUtils.near_vwap?(bars_1m),
      trapped_between_vwap: Entries::VWAPUtils.trapped_between_vwap_avwap?(bars_1m),

      # Volatility indicators
      range_10m_pct: Entries::RangeUtils.range_pct(bars_1m.last(10)),
      atr_downtrend: Entries::ATRUtils.atr_downtrend?(bars_1m),

      # Option chain indicators (simulated for historical data)
      ce_oi_up: false, # Cannot determine from historical data
      pe_oi_up: false, # Cannot determine from historical data
      iv: 15.0, # Default IV (assume reasonable IV for historical)
      iv_falling: false, # Cannot determine from historical data
      min_iv_threshold: instrument.symbol_name.include?('BANK') ? 13 : 10,
      spread_wide: false, # Cannot determine from historical data

      # Candle behavior
      avg_wick_ratio: Entries::CandleUtils.avg_wick_ratio(bars_1m.last(5)),

      # Timing
      time: current_time.strftime('%H:%M'),

      # Helper method
      time_between: ->(start_t, end_t) { time_between?(current_time.strftime('%H:%M'), start_t, end_t) }
    )
  end

  def calculate_adx_data_from_bars(bars)
    return { adx: 0, plus_di: 0, minus_di: 0 } if bars.size < 15

    series = CandleSeries.new(symbol: 'temp', interval: '5')
    bars.each { |c| series.add_candle(c) }

    return { adx: 0, plus_di: 0, minus_di: 0 } if series.candles.size < 15

    hlc = series.hlc
    result = TechnicalAnalysis::Adx.calculate(hlc, period: 14)
    return { adx: 0, plus_di: 0, minus_di: 0 } if result.empty?

    last_result = result.last

    adx_value = last_result.respond_to?(:adx) ? last_result.adx : (last_result.respond_to?(:adx_value) ? last_result.adx_value : 0)
    plus_di_value = if last_result.respond_to?(:plus_di)
                     last_result.plus_di
                   elsif last_result.respond_to?(:plusDi)
                     last_result.plusDi
                   else
                     0
                   end
    minus_di_value = if last_result.respond_to?(:minus_di)
                      last_result.minus_di
                    elsif last_result.respond_to?(:minusDi)
                      last_result.minusDi
                    else
                      0
                    end

    {
      adx: adx_value || 0,
      plus_di: plus_di_value || 0,
      minus_di: minus_di_value || 0
    }
  rescue StandardError => e
    Rails.logger.warn("[Backtest] ADX calculation failed: #{e.message}")
    series_value = series.adx(14) || 0
    { adx: series_value, plus_di: 0, minus_di: 0 }
  end

  def calculate_adx_for_series(series, index)
    return 0 if index < 14

    # Get last 14+ candles for ADX calculation
    recent_candles = series.candles[0..index]
    return 0 if recent_candles.size < 15

    temp_series = CandleSeries.new(symbol: 'temp', interval: '5')
    recent_candles.each { |c| temp_series.add_candle(c) }

    temp_series.adx(14) || 0
  end

  def decide_direction_from_supertrend_adx(st_result, adx_value, index)
    # Apply ADX filter if enabled
    if @adx_min_strength.positive? && adx_value < @adx_min_strength
      return :avoid
    end

    # Check Supertrend trend
    return :avoid if st_result.blank? || st_result[:trend].nil?

    case st_result[:trend]
    when :bullish
      :bullish
    when :bearish
      :bearish
    else
      :avoid
    end
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

  def find_5m_candle_index(series_5m, target_time)
    series_5m.candles.each_with_index do |candle, idx|
      return idx if candle.timestamp <= target_time && (idx == series_5m.candles.size - 1 || series_5m.candles[idx + 1].timestamp > target_time)
    end
    nil
  end

  def get_recent_5m_bars(series_5m, current_time, count)
    target_index = find_5m_candle_index(series_5m, current_time)
    return [] if target_index.nil?

    start_index = [0, target_index - count + 1].max
    series_5m.candles[start_index..target_index] || []
  end

  def time_between?(current_time_str, start_str, end_str)
    current = time_to_minutes(current_time_str)
    start_min = time_to_minutes(start_str)
    end_min = time_to_minutes(end_str)

    return false unless current && start_min && end_min

    if start_min <= end_min
      current >= start_min && current <= end_min
    else
      current >= start_min || current <= end_min
    end
  end

  def time_to_minutes(time_str)
    return nil unless time_str.is_a?(String)

    parts = time_str.split(':')
    return nil unless parts.size == 2

    hour = parts[0].to_i
    minute = parts[1].to_i

    hour * 60 + minute
  end

  def trading_hours?(timestamp)
    ist_time = timestamp.in_time_zone('Asia/Kolkata')
    hour = ist_time.hour
    minute = ist_time.min

    # Trading hours: 9:15 AM - 3:15 PM IST
    return false if hour < 9
    return false if hour == 9 && minute < 15
    return false if hour > 15
    return false if hour == 15 && minute > 15

    true
  end

  def enter_position(signal_result, candle, index)
    # Simulate entry at current spot price (for backtesting, we use spot price as proxy)
    entry_price = candle.close

    {
      signal_type: signal_result[:signal][:type],
      entry_index: index,
      entry_time: candle.timestamp,
      entry_price: entry_price,
      spot_entry_price: entry_price, # Store spot price for PnL calculation
      stop_loss: calculate_stop_loss(entry_price, signal_result[:signal][:type]),
      target: calculate_target(entry_price, signal_result[:signal][:type]),
      direction: signal_result[:direction]
    }
  end

  def calculate_stop_loss(entry_price, signal_type)
    if signal_type == :ce
      entry_price * 0.70 # -30%
    else
      entry_price * 1.30 # +30% (for PE, price going up is a loss)
    end
  end

  def calculate_target(entry_price, signal_type)
    if signal_type == :ce
      entry_price * 1.50 # +50%
    else
      entry_price * 0.50 # -50% (for PE, price going down is profit)
    end
  end

  def check_exit(position, candle, index, _series)
    # For backtesting, we simulate option PnL based on spot movement
    # This is a simplified model - in reality, option prices have delta, gamma, theta, vega
    current_spot = candle.close
    entry_spot = position[:spot_entry_price]
    signal_type = position[:signal_type]

    # Simplified PnL calculation (assumes 1:1 delta for ATM options)
    pnl_percent = if signal_type == :ce
                   ((current_spot - entry_spot) / entry_spot * 100)
                 else # :pe
                   ((entry_spot - current_spot) / entry_spot * 100)
                 end

    # Check target hit
    target_hit =
      (signal_type == :ce && current_spot >= position[:target]) ||
      (signal_type == :pe && current_spot <= position[:target])
    return build_exit_result(position, candle, index, pnl_percent, 'target') if target_hit

    # Check stop loss
    stop_loss_hit =
      (signal_type == :ce && current_spot <= position[:stop_loss]) ||
      (signal_type == :pe && current_spot >= position[:stop_loss])
    return build_exit_result(position, candle, index, pnl_percent, 'stop_loss') if stop_loss_hit

    # Time-based exit (3:15 PM IST)
    ist_time = candle.timestamp.in_time_zone('Asia/Kolkata')
    if ist_time.hour >= 15 && ist_time.min >= 15
      return build_exit_result(position, candle, index, pnl_percent, 'time_exit')
    end

    nil # No exit
  end

  def force_exit(position, candle, index, reason)
    current_spot = candle.close
    entry_spot = position[:spot_entry_price]
    signal_type = position[:signal_type]

    pnl_percent = if signal_type == :ce
                   ((current_spot - entry_spot) / entry_spot * 100)
                 else
                   ((entry_spot - current_spot) / entry_spot * 100)
                 end

    build_exit_result(position, candle, index, pnl_percent, reason)
  end

  def build_exit_result(position, candle, index, pnl_percent, exit_reason)
    {
      signal_type: position[:signal_type],
      entry_time: position[:entry_time],
      entry_price: position[:entry_price],
      exit_time: candle.timestamp,
      exit_price: candle.close,
      pnl_percent: pnl_percent.round(2),
      exit_reason: exit_reason,
      bars_held: index - position[:entry_index]
    }
  end

  def calculate_block_rate(stats)
    total_attempts = stats[:phase1_blocked] + stats[:signal_generated]
    return 0 if total_attempts.zero?

    ((stats[:phase1_blocked].to_f / total_attempts) * 100).round(2)
  end
end

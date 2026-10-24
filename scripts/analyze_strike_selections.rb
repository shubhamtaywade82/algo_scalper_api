# frozen_string_literal: true

# Script to analyze paper positions and validate strike selections
# Compares actual strike selected vs what should have been selected based on underlying spot price at entry time

require_relative '../config/environment'

class StrikeSelectionAnalyzer
  def initialize
    @results = []
    @errors = []
  end

  def analyze_all_paper_positions
    puts "\n#{'=' * 80}"
    puts 'STRIKE SELECTION ANALYSIS FOR PAPER POSITIONS'
    puts "#{'=' * 80}\n"

    paper_positions = PositionTracker.paper.includes(:watchable, :instrument).order(created_at: :desc)

    if paper_positions.empty?
      puts 'No paper positions found.'
      return
    end

    puts "Found #{paper_positions.count} paper position(s)\n\n"

    paper_positions.each_with_index do |position, idx|
      puts "\n[#{idx + 1}/#{paper_positions.count}] Analyzing position: #{position.order_no}"
      puts '-' * 80
      analyze_position(position)
    end
    # analyze_position(paper_positions.first)
    print_summary
  end

  private

  def analyze_position(position)
    # Get underlying instrument
    underlying_instrument = get_underlying_instrument(position)

    unless underlying_instrument
      @errors << { position: position.order_no, error: 'Could not find underlying instrument' }
      puts '  ❌ ERROR: Could not find underlying instrument'
      return
    end

    # Get derivative info - try watchable first, then find by security_id
    derivative = position.watchable if position.watchable.is_a?(Derivative)

    # If watchable is Instrument but segment is NSE_FNO or BSE_NFO, try to find derivative
    if !derivative && position.watchable.is_a?(Instrument) && %w[NSE_FNO BSE_FNO].include?(position.segment)
      exchange = position.segment == 'BSE_FNO' ? 'bse' : 'nse'

      derivative = Derivative.find_by(
        security_id: position.security_id.to_s,
        exchange: exchange
      )
    end

    # If still no derivative, try parsing symbol to extract strike info
    if !derivative && position.symbol.present?
      strike_info = parse_strike_from_symbol(position.symbol)
      if strike_info
        actual_strike = strike_info[:strike]
        option_type = strike_info[:option_type]
        underlying_symbol = strike_info[:underlying]
      else
        @errors << { position: position.order_no, error: 'Could not find derivative or parse strike from symbol' }
        puts '  ⚠️  SKIP: Could not find derivative or parse strike from symbol'
        return
      end
    elsif derivative
      actual_strike = derivative.strike_price.to_f
      option_type = derivative.option_type
      underlying_symbol = derivative.underlying_symbol || underlying_instrument.symbol_name
    else
      @errors << { position: position.order_no, error: 'Position is not a derivative (options/futures)' }
      puts '  ⚠️  SKIP: Position is not a derivative (index position?)'
      return
    end

    entry_time = position.created_at

    puts "  Entry Time: #{entry_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Underlying: #{underlying_symbol}"
    puts "  Actual Strike: #{actual_strike} (#{option_type})"

    # Get 1m OHLC data for entry time
    spot_price = get_spot_price_at_time(underlying_instrument, entry_time)
    unless spot_price
      @errors << { position: position.order_no, error: 'Could not fetch spot price at entry time' }
      puts '  ❌ ERROR: Could not fetch spot price at entry time'
      return
    end

    puts "  Spot Price at Entry: ₹#{spot_price.round(2)}"

    # Calculate expected ATM strike
    expected_strike = calculate_atm_strike(spot_price, underlying_symbol)
    unless expected_strike
      @errors << { position: position.order_no, error: 'Could not calculate expected ATM strike' }
      puts '  ❌ ERROR: Could not calculate expected ATM strike'
      return
    end

    puts "  Expected ATM Strike: #{expected_strike}"

    # Determine expected strikes based on direction
    direction = position.meta&.dig('direction') || (option_type == 'CE' ? 'bullish' : 'bearish')
    expected_strikes = calculate_expected_strikes(expected_strike, direction, underlying_symbol)

    puts "  Expected Strikes (#{direction}): #{expected_strikes.join(', ')}"

    # Check if actual strike matches expected
    strike_match = check_strike_match(actual_strike, expected_strikes, expected_strike, underlying_symbol)
    strike_diff = (actual_strike - expected_strike).abs

    result = {
      position_id: position.id,
      order_no: position.order_no,
      entry_time: entry_time,
      underlying_symbol: underlying_symbol,
      option_type: option_type,
      direction: direction,
      actual_strike: actual_strike,
      spot_price: spot_price,
      expected_atm_strike: expected_strike,
      expected_strikes: expected_strikes,
      strike_match: strike_match,
      strike_diff: strike_diff,
      strike_diff_pct: (strike_diff / expected_strike * 100.0).round(2)
    }

    @results << result

    # Print result
    if strike_match[:match]
      puts "  ✅ MATCH: Actual strike (#{actual_strike}) is in expected range"
    elsif strike_match[:close]
      puts "  ⚠️  CLOSE: Actual strike (#{actual_strike}) is close to expected (#{expected_strike}, diff: #{strike_diff.round(2)})"
    else
      puts "  ❌ MISMATCH: Actual strike (#{actual_strike}) differs from expected (#{expected_strike}, diff: #{strike_diff.round(2)})"
    end
  end

  def get_underlying_instrument(position)
    if position.watchable.is_a?(Derivative)
      # Get underlying instrument from derivative
      derivative = position.watchable
      underlying_security_id = derivative.underlying_security_id

      if underlying_security_id.present?
        # Find instrument by underlying security_id
        Instrument.find_by(
          exchange: derivative.exchange || 'nse',
          segment: 'index',
          security_id: underlying_security_id.to_s
        ) || derivative.instrument
      else
        derivative.instrument
      end
    elsif position.watchable.is_a?(Instrument)
      position.watchable
    else
      position.instrument
    end
  end

  def get_spot_price_at_time(instrument, entry_time)
    # Fetch 1m OHLC data for the day
    entry_date = entry_time.to_date

    # Use Market::Calendar to get last trading day (yesterday) as from_date and today as to_date
    # This ensures we get the most recent OHLC data including today
    last_trading_day = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:trading_days_ago)
                         Market::Calendar.trading_days_ago(1) # Get yesterday (1 trading day ago)
                       else
                         Time.zone.today - 1.day
                       end

    # For today's entries, use last trading day (yesterday) to today to get all available data
    # For past entries, use the entry date
    if entry_date == Time.zone.today
      from_date = last_trading_day.to_s
      to_date = Time.zone.today.to_s
    else
      from_date = entry_date.to_s
      to_date = entry_date.to_s
    end

    # Fetch 1m OHLC data - explicitly pass dates to override defaults
    # Note: intraday_ohlc has defaults that use MarketCalendar, but we override with explicit dates
    raw_data = instrument.intraday_ohlc(interval: '1', from_date: from_date, to_date: to_date, days: 1)

    # If no data and entry is today, try to get current LTP as fallback
    if raw_data.blank? && entry_date == Time.zone.today
      # Try multiple methods to get LTP
      ltp = instrument.ltp
      ltp ||= Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id.to_s)
      ltp ||= Live::RedisTickCache.instance.fetch_tick(instrument.exchange_segment,
                                                       instrument.security_id.to_s)&.dig(:ltp)&.to_f

      if ltp&.positive?
        puts "  ⚠️  Using current LTP as fallback (no historical OHLC available): ₹#{ltp.round(2)}"
        return ltp.to_f
      end
    end

    return nil if raw_data.blank?

    # Parse OHLC data
    candles = parse_ohlc_data(raw_data)
    return nil if candles.empty?

    # Find the candle that contains the entry time
    # Use the candle that starts before or at the entry time
    matching_candle = candles.find do |candle|
      candle_time = candle[:timestamp]
      next false unless candle_time

      # Candle contains entry time if entry_time is >= candle start and < candle start + 1 minute
      entry_time >= candle_time && entry_time < (candle_time + 1.minute)
    end

    # If no exact match, find the closest candle before entry time
    matching_candle ||= candles.select do |c|
      c[:timestamp] && c[:timestamp] <= entry_time
    end.max_by { |c| c[:timestamp] }

    return nil unless matching_candle

    # Use close price as spot (LTP approximation)
    matching_candle[:close]
  end

  def parse_ohlc_data(raw_data)
    return [] if raw_data.blank?

    if raw_data.is_a?(Array)
      raw_data.map do |row|
        {
          timestamp: parse_timestamp(row[:timestamp] || row['timestamp']),
          open: (row[:open] || row['open']).to_f,
          high: (row[:high] || row['high']).to_f,
          low: (row[:low] || row['low']).to_f,
          close: (row[:close] || row['close']).to_f,
          volume: (row[:volume] || row['volume']).to_i
        }
      end
    elsif raw_data.is_a?(Hash) && raw_data['high'].is_a?(Array)
      # DhanHQ format: { 'high' => [...], 'low' => [...], 'timestamp' => [epoch, ...], etc. }
      size = raw_data['high'].size
      (0...size).map do |i|
        # Try multiple possible keys for timestamp (timestamp, time, etc.)
        # DhanHQ returns epoch timestamps as Float values
        timestamp_val = raw_data['timestamp']&.[](i) ||
                        raw_data[:timestamp]&.[](i) ||
                        raw_data['time']&.[](i) ||
                        raw_data[:time]&.[](i)
        {
          timestamp: parse_timestamp(timestamp_val),
          open: raw_data['open'][i].to_f,
          high: raw_data['high'][i].to_f,
          low: raw_data['low'][i].to_f,
          close: raw_data['close'][i].to_f,
          volume: (raw_data['volume']&.[](i) || 0).to_i
        }
      end
    else
      []
    end
  end

  def parse_timestamp(ts)
    return nil if ts.nil?

    case ts
    when Time, DateTime, ActiveSupport::TimeWithZone
      ts.in_time_zone
    when Integer
      Time.zone.at(ts)
    when Float
      # Handle epoch timestamps (seconds since epoch)
      Time.zone.at(ts)
    when String
      # Try parsing as epoch first (numeric string)
      if ts.match?(/^\d+\.?\d*$/)
        Time.zone.at(ts.to_f)
      else
        Time.zone.parse(ts)
      end
    end
  end

  def calculate_atm_strike(spot_price, underlying_symbol)
    # Get strike interval based on underlying
    strike_interval = get_strike_interval(underlying_symbol)
    return nil unless strike_interval

    # Round to nearest strike
    (spot_price / strike_interval).round * strike_interval
  end

  def parse_strike_from_symbol(symbol)
    # Parse symbols like "NIFTY-Dec2025-26200-PE" or "BANKNIFTY25JAN26200CE"
    return nil if symbol.blank?

    symbol_str = symbol.to_s.upcase

    # Pattern 1: NIFTY-Dec2025-26200-PE or NIFTY-25DEC-26200-PE
    if (match = symbol_str.match(/^(\w+)-.*?(\d{5})-?(CE|PE)$/))
      underlying = match[1]
      strike = match[2].to_f
      option_type = match[3]
      return { underlying: underlying, strike: strike, option_type: option_type }
    end

    # Pattern 2: BANKNIFTY25JAN26200CE (no dashes)
    if (match = symbol_str.match(/^(\w+)(\d{2}[A-Z]{3})(\d{5})(CE|PE)$/))
      underlying = match[1]
      strike = match[3].to_f
      option_type = match[4]
      return { underlying: underlying, strike: strike, option_type: option_type }
    end

    # Pattern 3: NIFTY 25 DEC 26200 PE (with spaces)
    if (match = symbol_str.match(/^(\w+)\s+(\d{2}\s+[A-Z]{3}\s+)?(\d{5})\s*(CE|PE)$/))
      underlying = match[1]
      strike = match[3].to_f
      option_type = match[4]
      return { underlying: underlying, strike: strike, option_type: option_type }
    end

    nil
  end

  def get_strike_interval(underlying_symbol)
    symbol_up = underlying_symbol.to_s.upcase
    case symbol_up
    when 'NIFTY', 'NIFTY 50'
      50
    when 'BANKNIFTY', 'BANK NIFTY', 'NIFTY BANK'
      100
    when 'FINNIFTY', 'FIN NIFTY', 'NIFTY FIN'
      50
    when 'MIDCPNIFTY', 'MIDCP NIFTY', 'NIFTY MIDCAP'
      25
    when 'SENSEX'
      100
    else
      # Default to 50 for unknown indices
      50
    end
  end

  def calculate_expected_strikes(atm_strike, direction, underlying_symbol)
    strike_interval = get_strike_interval(underlying_symbol)
    return [] unless strike_interval

    if %w[bullish ce].include?(direction.to_s.downcase)
      # CE: ATM, ATM+1, ATM+2, ATM+3
      [
        atm_strike,
        atm_strike + strike_interval,
        atm_strike + (2 * strike_interval),
        atm_strike + (3 * strike_interval)
      ].first(3)
    else
      # PE: ATM, ATM-1, ATM-2, ATM-3
      [
        atm_strike,
        atm_strike - strike_interval,
        atm_strike - (2 * strike_interval),
        atm_strike - (3 * strike_interval)
      ].first(3)
    end
  end

  def check_strike_match(actual_strike, expected_strikes, expected_atm, underlying_symbol)
    # Check if actual strike is in expected list
    if expected_strikes.any? { |s| (actual_strike - s).abs < 0.01 }
      { match: true, close: false }
    else
      strike_interval = get_strike_interval(underlying_symbol)
      if strike_interval && (actual_strike - expected_atm).abs <= strike_interval * 2
        # Within 2 strikes of ATM
        { match: false, close: true }
      else
        { match: false, close: false }
      end
    end
  end

  def print_summary
    puts "\n#{'=' * 80}"
    puts 'SUMMARY'
    puts "#{'=' * 80}\n"

    total = @results.size
    matches = @results.count { |r| r[:strike_match][:match] }
    close_matches = @results.count { |r| r[:strike_match][:close] && !r[:strike_match][:match] }
    mismatches = @results.count { |r| !r[:strike_match][:match] && !r[:strike_match][:close] }

    puts "Total Positions Analyzed: #{total}"
    puts "✅ Exact Matches: #{matches} (#{(matches.to_f / total * 100).round(1)}%)"
    puts "⚠️  Close Matches: #{close_matches} (#{(close_matches.to_f / total * 100).round(1)}%)"
    puts "❌ Mismatches: #{mismatches} (#{(mismatches.to_f / total * 100).round(1)}%)"

    if @errors.any?
      puts "\nErrors: #{@errors.size}"
      @errors.each do |error|
        puts "  - #{error[:position]}: #{error[:error]}"
      end
    end

    if mismatches.positive?
      puts "\n#{'-' * 80}"
      puts 'MISMATCH DETAILS:'
      puts '-' * 80
      @results.select { |r| !r[:strike_match][:match] && !r[:strike_match][:close] }.each do |result|
        puts "\nOrder: #{result[:order_no]}"
        puts "  Entry: #{result[:entry_time].strftime('%Y-%m-%d %H:%M:%S')}"
        puts "  Underlying: #{result[:underlying_symbol]} (#{result[:option_type]})"
        puts "  Spot at Entry: ₹#{result[:spot_price].round(2)}"
        puts "  Expected ATM: #{result[:expected_atm_strike]}"
        puts "  Expected Strikes: #{result[:expected_strikes].join(', ')}"
        puts "  Actual Strike: #{result[:actual_strike]}"
        puts "  Difference: #{result[:strike_diff].round(2)} (#{result[:strike_diff_pct]}%)"
      end
    end

    puts "\n#{'=' * 80}"
  end
end

# Run the analysis
if __FILE__ == $PROGRAM_NAME
  analyzer = StrikeSelectionAnalyzer.new
  analyzer.analyze_all_paper_positions
end

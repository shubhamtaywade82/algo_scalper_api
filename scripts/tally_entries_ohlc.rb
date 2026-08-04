# frozen_string_literal: true

require 'bigdecimal'

def tally_positions
  # Target positions
  ids = [3578, 3577, 3580, 3579]
  positions = PositionTracker.where(id: ids)

  puts "Found #{positions.count} positions to tally."
  puts "------------------------------------------------"

  positions.each do |p|
    puts "\nPosition ID: #{p.id}, Symbol: #{p.symbol}"
    puts "  SID: #{p.security_id}, Segment: #{p.segment}"

    # Create a temporary instrument-like object to call intraday_ohlc
    # or use Derivative model directly
    derivative = Derivative.find_by(security_id: p.security_id) ||
                 Derivative.find_by(symbol_name: p.symbol)

    unless derivative
      puts "  ❌ ERROR: Could not find derivative in database for SID #{p.security_id}"
      next
    end

    puts "  Derivative found: #{derivative.display_name} (#{derivative.security_id})"

    # Fetch 1m OHLC for today (2026-03-11)
    ohlc_data = derivative.intraday_ohlc(interval: '1', days: 1)
    if ohlc_data.blank?
      puts "  ❌ ERROR: No OHLC data returned for #{p.symbol}"
      next
    end

    # Load into CandleSeries
    series = CandleSeries.new(symbol: p.symbol, interval: '1')
    series.load_from_raw(ohlc_data)
    puts "  Fetched #{series.candles.size} 1m candles."

    entry_time = p.created_at
    entry_price = p.entry_price.to_f

    # Find matching candle (1m window)
    candle_time = entry_time.beginning_of_minute
    candle = series.candles.find { |c| c.timestamp == candle_time }

    if candle
      within_range = entry_price.between?(candle.low.to_f, candle.high.to_f)
      range_str = "[L: #{candle.low.to_f}, H: #{candle.high.to_f}]"

      if within_range
        puts "  ✅ MATCH @ #{entry_time.strftime('%H:%M:%S')}: Entry #{entry_price} is WITHIN candle range #{range_str}"
      else
        # Try previous candle
        prev_candle = series.candles.find { |c| c.timestamp == candle_time - 1.minute }
        if prev_candle && entry_price >= prev_candle.low.to_f && entry_price <= prev_candle.high.to_f
           puts "  ⚠️  LAG @ #{entry_time.strftime('%H:%M:%S')}: Entry #{entry_price} is in PREVIOUS candle [L: #{prev_candle.low.to_f}, H: #{prev_candle.high.to_f}]"
        else
           puts "  ❌ MISMATCH @ #{entry_time.strftime('%H:%M:%S')}: Entry #{entry_price} is OUTSIDE candle range #{range_str}"
           puts "     Candle O: #{candle.open.to_f}, C: #{candle.close.to_f}"
        end
      end
    else
      puts "  ❓ No matching 1m candle found at #{candle_time.strftime('%H:%M:%S')}"
    end
  end
end

tally_positions

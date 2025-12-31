# frozen_string_literal: true

# SMC Console Example - Fetch candles for NIFTY and SENSEX
# Usage: Load this file in Rails console
#
# Example:
#   load 'lib/console/smc_example.rb'
#   fetch_nifty_and_sensex_candles

# Load helpers first
load 'lib/console/smc_helpers.rb'

def fetch_nifty_and_sensex_candles
  puts "\n#{'=' * 80}"
  puts '  Fetching Candles for NIFTY and SENSEX'
  puts '=' * 80

  # Fetch NIFTY
  puts "\n📊 Fetching NIFTY candles..."
  nifty = Instrument.find_by_sid_and_segment(
    security_id: "13",
    segment_code: "IDX_I",
    symbol_name: "NIFTY"
  )

  if nifty
    puts "  Instrument: #{nifty.symbol_name} (ID: #{nifty.security_id})"

    print "  Fetching 1H... "
    nifty_1h = fetch_candles_with_history(nifty, interval: "60", target_candles: 60, delay_seconds: 1.0)
    puts "#{nifty_1h&.candles&.count || 0} candles"

    print "  Fetching 15m... "
    nifty_15m = fetch_candles_with_history(nifty, interval: "15", target_candles: 100, delay_seconds: 1.0)
    puts "#{nifty_15m&.candles&.count || 0} candles"

    print "  Fetching 5m... "
    nifty_5m = fetch_candles_with_history(nifty, interval: "5", target_candles: 150, delay_seconds: 1.0)
    puts "#{nifty_5m&.candles&.count || 0} candles"

    # Store in variables for easy access
    $nifty_1h = nifty_1h
    $nifty_15m = nifty_15m
    $nifty_5m = nifty_5m
  else
    puts "  ❌ NIFTY instrument not found"
  end

  # Fetch SENSEX
  puts "\n📊 Fetching SENSEX candles..."
  sensex = Instrument.find_by_sid_and_segment(
    security_id: "51",
    segment_code: "IDX_I",
    symbol_name: "SENSEX"
  )

  if sensex
    puts "  Instrument: #{sensex.symbol_name} (ID: #{sensex.security_id})"

    print "  Fetching 1H... "
    sensex_1h = fetch_candles_with_history(sensex, interval: "60", target_candles: 60, delay_seconds: 1.0)
    puts "#{sensex_1h&.candles&.count || 0} candles"

    print "  Fetching 15m... "
    sensex_15m = fetch_candles_with_history(sensex, interval: "15", target_candles: 100, delay_seconds: 1.0)
    puts "#{sensex_15m&.candles&.count || 0} candles"

    print "  Fetching 5m... "
    sensex_5m = fetch_candles_with_history(sensex, interval: "5", target_candles: 150, delay_seconds: 1.0)
    puts "#{sensex_5m&.candles&.count || 0} candles"

    # Store in variables for easy access
    $sensex_1h = sensex_1h
    $sensex_15m = sensex_15m
    $sensex_5m = sensex_5m
  else
    puts "  ❌ SENSEX instrument not found"
  end

  puts "\n#{'=' * 80}"
  puts "  Available Variables:"
  puts "=" * 80
  puts "  NIFTY:  $nifty_1h, $nifty_15m, $nifty_5m"
  puts "  SENSEX: $sensex_1h, $sensex_15m, $sensex_5m"
  puts "\nExample usage:"
  puts "  Smc::Context.new($nifty_1h)"
  puts "  Smc::BiasEngine.new(nifty).details"
  puts "\n"
end

puts "\n#{'=' * 80}"
puts '  SMC Example Script Loaded'
puts '=' * 80
puts "\nRun: fetch_nifty_and_sensex_candles"
puts "\n"


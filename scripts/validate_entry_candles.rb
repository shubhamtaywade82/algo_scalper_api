# frozen_string_literal: true

# Usage: rails runner scripts/validate_entry_candles.rb
# Filters:
#   POSITION_IDS=1,2,3   rails runner scripts/validate_entry_candles.rb
#   SYMBOLS=NIFTY,BANKNIFTY rails runner scripts/validate_entry_candles.rb
#   STATUS=active         rails runner scripts/validate_entry_candles.rb (default: all)
#   DATE_FROM=2026-03-10  rails runner scripts/validate_entry_candles.rb
#   DATE_TO=2026-03-11    rails runner scripts/validate_entry_candles.rb

def parse_ids
  (ENV['POSITION_IDS'] || '').split(',').map(&:strip).reject(&:empty?).map(&:to_i)
end

def parse_symbols
  (ENV['SYMBOLS'] || '').split(',').map(&:strip).reject(&:empty?)
end

def filter_scope(scope)
  ids = parse_ids
  symbols = parse_symbols
  status = ENV.fetch('STATUS', nil)
  date_from = ENV.fetch('DATE_FROM', nil)
  date_to = ENV.fetch('DATE_TO', nil)

  scope = scope.where(id: ids) if ids.any?
  scope = scope.where(symbol: symbols) if symbols.any?
  scope = scope.where(status: status) if status.present?
  scope = scope.where(created_at: Date.parse(date_from).beginning_of_day..) if date_from
  scope = scope.where(created_at: ..Date.parse(date_to).end_of_day) if date_to
  scope
end

def find_watchable(position)
  if position.watchable_type == 'Derivative'
    position.watchable
  else
    Derivative.find_by(security_id: position.security_id) ||
      Derivative.find_by(symbol_name: position.symbol)
  end
end

def fetch_ohlc(watchable, position)
  entry_date = position.created_at.to_date
  days = (Time.zone.today - entry_date).to_i + 2
  days = [days, 10].min

  data = watchable.intraday_ohlc(interval: '1', days: days)
  return nil if data.blank?

  series = CandleSeries.new(symbol: position.symbol, interval: '1')
  series.load_from_raw(data)
  series
end

def format_price(price)
  return 'N/A' unless price
  "₹#{format('%.2f', price)}"
end

def find_candle(series, entry_time)
  series.candles.find { |c| c.timestamp == entry_time.beginning_of_minute }
end

TIMESTAMP_LABELS = {
  created_at: 'created_at',
  signal_timestamp: 'signal_timestamp'
}.freeze

def check_candle_for_time(series, entry_time, entry_price)
  candle = find_candle(series, entry_time)
  return { candle: nil, within: false, prev_match: false } unless candle

  within = entry_price.between?(candle.low.to_f, candle.high.to_f)
  prev_candle = series.candles.find { |c| c.timestamp == entry_time.beginning_of_minute - 60 }
  prev_match = prev_candle && entry_price.between?(prev_candle.low.to_f, prev_candle.high.to_f)

  { candle: candle, prev_candle: prev_candle, within: within, prev_match: prev_match }
end

def validate_position(position)
  watchable = find_watchable(position)
  unless watchable
    return { position: position, error: "No Derivative/Instrument found for SID #{position.security_id}" }
  end

  series = fetch_ohlc(watchable, position)
  unless series
    return { position: position, error: 'No OHLC data returned' }
  end

  entry_price = position.entry_price&.to_f
  unless entry_price
    return { position: position, error: "No entry price" }
  end

  best = nil

  TIMESTAMP_LABELS.each do |field, label|
    ts = position.public_send(field)
    next unless ts

    result = check_candle_for_time(series, ts, entry_price)
    match = result[:within] || result[:prev_match]
    next unless best.nil? || (match && !best[:matched])
    best = { position: position, field: field, label: label, entry_time: ts, entry_price: entry_price,
             candle_count: series.candles.size, candle: result[:candle], prev_candle: result[:prev_candle],
             within: result[:within], prev_match: result[:prev_match],
             matched: match }
  end

  return best if best

  { position: position, error: 'No timestamp available (created_at and signal_timestamp both nil)',
    entry_price: entry_price }
end

def format_ts_info(field, label, entry_time, position)
  other = TIMESTAMP_LABELS.keys.find { |f| f != field }
  other_ts = position.public_send(other)
  other_str = other_ts ? other_ts.strftime('%H:%M:%S') : 'N/A'
  "via #{label} (#{entry_time.strftime('%H:%M:%S')}, other: #{other_str})"
end

def display_result(result)
  pos = result[:position]

  if result[:error]
    entry_price = result[:entry_price] || pos.entry_price.to_f
    puts "  #{pos.id} #{pos.symbol} #{format_price(entry_price)} — ❌ #{result[:error]}"
    return
  end

  candle = result[:candle]
  entry_price = result[:entry_price]
  entry_time = result[:entry_time]
  ts_info = format_ts_info(result[:field], result[:label], entry_time, pos)

  unless candle
    puts "  #{pos.id} #{pos.symbol} #{format_price(entry_price)} #{ts_info} — " \
         "❓ No candle at entry minute (#{result[:candle_count]} candles)"
    return
  end

  range_str = "[#{format_price(candle.low)}, #{format_price(candle.high)}]"

  if result[:within]
    puts "  #{pos.id} #{pos.symbol} #{format_price(entry_price)} #{ts_info} — ✅ WITHIN #{range_str} " \
         "(O: #{format_price(candle.open)}, C: #{format_price(candle.close)}, V: #{candle.volume})"
  elsif result[:prev_match]
    puts "  #{pos.id} #{pos.symbol} #{format_price(entry_price)} #{ts_info} — ⚠️  LAG " \
         "(entry in PREVIOUS candle) [#{format_price(result[:prev_candle].low)}, #{format_price(result[:prev_candle].high)}] " \
         "(vs current #{range_str})"
  else
    puts "  #{pos.id} #{pos.symbol} #{format_price(entry_price)} #{ts_info} — ❌ OUTSIDE #{range_str} " \
         "(O: #{format_price(candle.open)}, C: #{format_price(candle.close)})"
    low_dev = ((entry_price - candle.low.to_f) / candle.low.to_f * 100).round(3)
    high_dev = ((entry_price - candle.high.to_f) / candle.high.to_f * 100).round(3)
    puts "     Deviation from low: #{'+' if low_dev.positive?}#{low_dev}%, from high: #{'+' if high_dev.positive?}#{high_dev}%"
  end
end

scope = filter_scope(PositionTracker.all)
positions = scope.order(:created_at).to_a

puts "Found #{positions.size} position(s) to validate."
puts '-' * 80

stats = { ok: 0, lag: 0, mismatch: 0, error: 0 }

positions.each do |pos|
  result = validate_position(pos)
  display_result(result)

  if result[:error]
    stats[:error] += 1
  elsif result[:within]
    stats[:ok] += 1
  elsif result[:prev_match]
    stats[:lag] += 1
  else
    stats[:mismatch] += 1
  end
end

puts '-' * 80
puts "Summary: #{stats[:ok]} ✅ within, #{stats[:lag]} ⚠️  lag, " \
     "#{stats[:mismatch]} ❌ outside, #{stats[:error]} ❌ error (total: #{positions.size})"

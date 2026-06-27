# frozen_string_literal: true

# Usage: bundle exec rake trading:validate_entry_candles
# Filters:
#   POSITION_IDS=1,2,3         bundle exec rake trading:validate_entry_candles
#   SYMBOLS=NIFTY,BANKNIFTY    bundle exec rake trading:validate_entry_candles
#   STATUS=active              bundle exec rake trading:validate_entry_candles
#   DATE_FROM=2026-03-24       bundle exec rake trading:validate_entry_candles
#   DATE_TO=2026-06-23         bundle exec rake trading:validate_entry_candles

TIMESTAMP_LABELS = {
  created_at: 'created_at',
  signal_timestamp: 'signal_timestamp'
}.freeze

META_ENTRY_AT_KEY = 'entry_at'

namespace :trading do
  desc 'Validate position entry prices against 1m OHLCV candles'
  task validate_entry_candles: :environment do
    require 'bigdecimal'

    scope = filter_scope(PositionTracker.all)
    positions = scope.order(:created_at).to_a

    puts "Found #{positions.size} position(s) to validate."
    puts '-' * 80

    stats = { ok: 0, lag: 0, mismatch: 0, error: 0 }
    deviations = []

    positions.each do |pos|
      result = validate_position(pos)
      display_result(result)

      if result[:error]
        stats[:error] += 1
        deviations << { pos: pos, type: :error, detail: result[:error] }
      elsif result[:within]
        stats[:ok] += 1
      elsif result[:prev_match]
        stats[:lag] += 1
        deviations << { pos: pos, type: :lag,
                        ts_info: format_ts_info_short(result),
                        candle_low: result[:prev_candle].low.to_f,
                        candle_high: result[:prev_candle].high.to_f }
      else
        stats[:mismatch] += 1
        dev_low = ((result[:entry_price] - result[:candle].low.to_f) / result[:candle].low.to_f * 100).round(2)
        dev_high = ((result[:entry_price] - result[:candle].high.to_f) / result[:candle].high.to_f * 100).round(2)
        c = result[:candle]
        near_open = ((result[:entry_price] - c.open.to_f) / c.open.to_f * 100).round(2)
        near_close = ((result[:entry_price] - c.close.to_f) / c.close.to_f * 100).round(2)
        spread_pct = (((c.high.to_f - c.low.to_f) / c.low.to_f) * 100).round(2)
        deviations << { pos: pos, type: :outside,
                        ts_info: format_ts_info_short(result),
                        entry_price: result[:entry_price],
                        candle_low: c.low.to_f, candle_high: c.high.to_f,
                        candle_open: c.open.to_f, candle_close: c.close.to_f,
                        near_open: near_open, near_close: near_close,
                        spread_pct: spread_pct, candle_volume: c.volume,
                        dev_low: dev_low, dev_high: dev_high }
      end
    end

    puts '-' * 80
    puts "Summary: #{stats[:ok]} ✅ within, #{stats[:lag]} ⚠️  lag, " \
         "#{stats[:mismatch]} ❌ outside, #{stats[:error]} ❌ error (total: #{positions.size})"

    if deviations.any?
      puts
      puts '=' * 80
      puts 'DEVIATION REPORT — positions where entry price falls outside candle range'
      puts '=' * 80
      deviations.each do |d|
        p = d[:pos]
        meta_at_raw = p.meta&.[](META_ENTRY_AT_KEY)
        meta_at_str = if meta_at_raw
                        t = Time.zone.parse(meta_at_raw.to_s) rescue nil
                        t ? t.strftime('%H:%M:%S') : meta_at_raw.to_s
                      else
                        '-'
                      end
        suffix = "side=#{p.side} state=#{p.trade_state} path=#{p.entry_path || '-'} " \
                 "paper=#{p.paper} meta_entry_at=#{meta_at_str}"
        case d[:type]
        when :outside
          candle_range = format_price(d[:candle_high]).to_s == format_price(d[:candle_low]).to_s ?
                         format_price(d[:candle_low]) :
                         "#{format_price(d[:candle_low])}–#{format_price(d[:candle_high])}"
          match_open = d[:near_open].abs <= 3 ? " ≈open(#{format_price(d[:candle_open])})" : ""
          match_close = d[:near_close].abs <= 3 ? " ≈close(#{format_price(d[:candle_close])})" : ""
          spread_note = d[:candle_volume] && d[:candle_volume] < 50_000 ? " thin_vol" : ""
          puts format("  %-4d %-30s %s entry=%s candle=[%s] dev_low=%+.2f%% dev_high=%+.2f%% | spread=%.2f%%%s%s%s  | %s",
                      p.id, p.symbol, d[:ts_info],
                      format_price(d[:entry_price]),
                      candle_range,
                      d[:dev_low], d[:dev_high],
                      d[:spread_pct], match_open, match_close, spread_note, suffix)
        when :lag
          puts format("  %-4d %-30s %s entry in PREV candle [%s, %s]  | %s",
                      p.id, p.symbol, d[:ts_info],
                      format_price(d[:candle_low]), format_price(d[:candle_high]), suffix)
        when :error
          puts "  #{p.id} #{p.symbol} — ❌ #{d[:detail]}  | #{suffix}"
        end
      end
      puts '-' * 80
      puts "Total: #{deviations.size} position(s) with deviations"
    end
  end
end

def parse_ids
  (ENV['POSITION_IDS'] || '').split(',').map(&:strip).reject(&:empty?).map(&:to_i)
end

def parse_symbols
  (ENV['SYMBOLS'] || '').split(',').map(&:strip).reject(&:empty?)
end

def filter_scope(scope)
  ids = parse_ids
  symbols = parse_symbols
  status = ENV['STATUS']
  date_from = ENV['DATE_FROM']
  date_to = ENV['DATE_TO']

  scope = scope.where(id: ids) if ids.any?
  scope = scope.where(symbol: symbols) if symbols.any?
  scope = scope.where(status: status) if status.present?
  scope = scope.where('created_at >= ?', Date.parse(date_from).beginning_of_day) if date_from
  scope = scope.where('created_at <= ?', Date.parse(date_to).end_of_day) if date_to
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
  days = (Date.today - entry_date).to_i + 2
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

  seg = watchable.exchange_segment rescue position.segment
  if seg.to_s == 'BSE_FNO'
    return { position: position, error: "DhanHQ has no OHLCV data for BSE_FNO (SENSEX options) — platform limitation" }
  end

  series = fetch_ohlc(watchable, position)
  unless series
    return { position: position, error: 'No OHLC data returned — empty from DhanHQ' }
  end

  entry_price = position.entry_price&.to_f
  unless entry_price
    return { position: position, error: 'No entry price' }
  end

  best = nil

  TIMESTAMP_LABELS.each do |field, label|
    ts = position.public_send(field)
    next unless ts

    result = check_candle_for_time(series, ts, entry_price)
    match = result[:within] || result[:prev_match]
    if best.nil? || (match && !best[:matched])
      best = { position: position, field: field, label: label, entry_time: ts, entry_price: entry_price,
               candle_count: series.candles.size, candle: result[:candle], prev_candle: result[:prev_candle],
               within: result[:within], prev_match: result[:prev_match],
               matched: match }
    end
  end

  # Also try meta['entry_at'] if available
  meta_ts = position.meta&.[](META_ENTRY_AT_KEY)
  if meta_ts
    meta_ts = Time.zone.parse(meta_ts.to_s) rescue nil
    if meta_ts
      result = check_candle_for_time(series, meta_ts, entry_price)
      match = result[:within] || result[:prev_match]
      if best.nil? || (match && !best[:matched])
        best = { position: position, field: nil, label: "meta[#{META_ENTRY_AT_KEY}]", entry_time: meta_ts,
                 entry_price: entry_price, candle_count: series.candles.size,
                 candle: result[:candle], prev_candle: result[:prev_candle],
                 within: result[:within], prev_match: result[:prev_match],
                 matched: match }
      end
    end
  end

  return best if best

  { position: position, error: 'No timestamp available (created_at and signal_timestamp both nil)',
    entry_price: entry_price }
end

def format_ts_info_short(result)
  "via #{result[:label]} #{result[:entry_time].strftime('%H:%M:%S')}"
end

def format_ts_info(field, label, entry_time, position)
  if field
    other = TIMESTAMP_LABELS.keys.find { |f| f != field }
    other_ts = position.public_send(other) if other
    other_str = other_ts ? other_ts.strftime('%H:%M:%S') : 'N/A'
  else
    created = position.created_at
    signal = position.signal_timestamp
    other_str = if created && signal
                  "created=#{created.strftime('%H:%M:%S')} signal=#{signal.strftime('%H:%M:%S')}"
                elsif created
                  "created=#{created.strftime('%H:%M:%S')} signal=N/A"
                else
                  'N/A'
                end
  end
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
    puts "     Deviation from low: #{low_dev.positive? ? '+' : ''}#{low_dev}%, from high: #{high_dev.positive? ? '+' : ''}#{high_dev}%"
  end
end

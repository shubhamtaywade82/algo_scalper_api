#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "optparse"
require "json"
require "date"
require "time"
require "fileutils"

options = {
  exchange_segment: "IDX_I",
  options_exchange_segment: "NSE_FNO",
  symbol: "NIFTY",
  interval: "1",
  days: 30,
  expiry_flag: "WEEK",
  expiry_code: 0,
  out_dir: File.join(__dir__, "..", "tmp", "optimization"),
  client_path: ENV["DHANHQ_CLIENT_PATH"] || File.expand_path("../../dhanhq-client", __dir__)
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/calibrate_options_policy.rb [options]"
  opts.on("--exchange-segment SEG", "Exchange segment (e.g. IDX_I)") { |value| options[:exchange_segment] = value }
  opts.on("--options-exchange-segment SEG", "Expired options segment (default NSE_FNO)") { |value| options[:options_exchange_segment] = value }
  opts.on("--symbol SYMBOL", "Underlying symbol (e.g. NIFTY)") { |value| options[:symbol] = value }
  opts.on("--interval INT", "Interval (1,5,15,25,60)") { |value| options[:interval] = value }
  opts.on("--days N", Integer, "How many days back from today") { |value| options[:days] = value }
  opts.on("--expiry-flag FLAG", "WEEK or MONTH") { |value| options[:expiry_flag] = value.upcase }
  opts.on("--expiry-code N", Integer, "Expiry code") { |value| options[:expiry_code] = value }
  opts.on("--out-dir DIR", "Output directory") { |value| options[:out_dir] = value }
end.parse!

require File.join(options[:client_path], "lib", "dhan_hq")
DhanHQ.configure_with_env

instrument = DhanHQ::Models::Instrument.find(options[:exchange_segment], options[:symbol], exact_match: true)
abort "Instrument not found for #{options[:exchange_segment]}:#{options[:symbol]}" if instrument.nil?

to_date = Date.today
to_date -= 1 if to_date.saturday?
to_date -= 2 if to_date.sunday?
effective_days = [options[:days], 20].min
from_date = to_date - effective_days
from_date -= 1 if from_date.saturday?
from_date -= 2 if from_date.sunday?

def average_forward_return(expired_data)
  candles = expired_data.to_candles
  return nil if candles.size < 2

  closes = candles.map { |row| row[:close].to_f }
  forward_returns = closes.each_cons(2).map { |a, b| ((b - a) / a) * 100.0 }
  return nil if forward_returns.empty?

  forward_returns.sum / forward_returns.size
end

def moneyness_for(strike, side)
  return :atm if strike == "ATM"

  offset = strike.sub("ATM", "").to_i
  return :atm if offset.zero?

  if side == "CALL"
    offset.positive? ? :otm : :itm
  else
    offset.positive? ? :itm : :otm
  end
end

def evaluate_strikes(instrument:, options:, side:, strikes:, from_date:, to_date:)
  rows = []
  errors = []

  strikes.each do |strike|
    begin
      expired_data = fetch_with_fallbacks(
        instrument: instrument,
        options: options,
        side: side,
        strike: strike,
        from_date: from_date,
        to_date: to_date
      )
      avg_return = average_forward_return(expired_data)
      next if avg_return.nil?

      rows << {
        side: side,
        strike: strike,
        moneyness: moneyness_for(strike, side),
        avg_forward_return_pct: avg_return.round(6),
        avg_volume: expired_data.average_volume(side),
        avg_open_interest: expired_data.average_open_interest(side),
        avg_implied_volatility: expired_data.average_implied_volatility(side)
      }
    rescue StandardError
      errors << { side: side, strike: strike, error: $ERROR_INFO.message }
    end
  end

  [rows, errors]
end

def fetch_with_fallbacks(instrument:, options:, side:, strike:, from_date:, to_date:)
  segments = [options[:options_exchange_segment], options[:exchange_segment], "NSE_FNO", "IDX_I"].uniq
  expiry_codes = [1]
  last_error = nil

  segments.each do |segment|
    expiry_codes.each do |expiry_code|
      begin
        data = DhanHQ::Models::ExpiredOptionsData.fetch(
          exchange_segment: segment,
          interval: options[:interval],
          security_id: instrument.security_id.to_i,
          instrument: "OPTIDX",
          expiry_flag: options[:expiry_flag],
          expiry_code: expiry_code,
          strike: strike,
          drv_option_type: side,
          required_data: %w[close volume oi iv strike spot],
          from_date: from_date.strftime("%Y-%m-%d"),
          to_date: to_date.strftime("%Y-%m-%d")
        )
        return data if data.to_candles.any?
      rescue StandardError
        last_error = $ERROR_INFO
      end
    end
  end

  raise(last_error || StandardError.new("no expired options data for probed segment/expiry combinations"))
end

strikes = %w[ATM ATM+1 ATM-1 ATM+2 ATM-2]
call_rows, call_errors = evaluate_strikes(
  instrument: instrument,
  options: options,
  side: "CALL",
  strikes: strikes,
  from_date: from_date,
  to_date: to_date
)
put_rows, put_errors = evaluate_strikes(
  instrument: instrument,
  options: options,
  side: "PUT",
  strikes: strikes,
  from_date: from_date,
  to_date: to_date
)

if call_rows.empty? && put_rows.empty?
  puts JSON.pretty_generate(
    decision: :no_policy,
    reason: "no expired options samples could be evaluated",
    symbol: options[:symbol],
    exchange_segment: options[:exchange_segment],
    probe_errors: call_errors + put_errors
  )
  exit 0
end

best_call = call_rows.max_by { |row| row[:avg_forward_return_pct] }
best_put = put_rows.max_by { |row| row[:avg_forward_return_pct] }

policy = {
  min_trend_adx: 18.0,
  moderate_trend_adx: 25.0,
  strong_trend_adx: 35.0,
  preferred_moneyness: {
    ce: (best_call && best_call[:moneyness]) || :atm,
    pe: (best_put && best_put[:moneyness]) || :atm
  }
}

payload = {
  generated_at: Time.now.utc.iso8601,
  source_window: {
    exchange_segment: options[:exchange_segment],
    symbol: options[:symbol],
    security_id: instrument.security_id,
    interval: options[:interval],
    from: from_date.strftime("%Y-%m-%d"),
    to: to_date.strftime("%Y-%m-%d"),
    days: options[:days],
    effective_days: effective_days
  },
  calibration: {
    expiry_flag: options[:expiry_flag],
    expiry_code: options[:expiry_code],
    strikes_tested: strikes,
    call_rows: call_rows,
    put_rows: put_rows,
    call_probe_errors: call_errors,
    put_probe_errors: put_errors
  },
  policy: policy
}

FileUtils.mkdir_p(options[:out_dir])
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
path = File.join(options[:out_dir], "options_policy_#{timestamp}.json")
File.write(path, JSON.pretty_generate(payload))

puts "Generated policy JSON: #{path}"
puts "Preferred CE moneyness: #{policy.dig(:preferred_moneyness, :ce)}"
puts "Preferred PE moneyness: #{policy.dig(:preferred_moneyness, :pe)}"

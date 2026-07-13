#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "optparse"
require "json"
require "dhan_hq_api_bars"
require "super_trend_signal_generator"
require "options_buying_policy"
require "live_option_selector"

options = {
  exchange_segment: "IDX_I",
  symbol: "NIFTY",
  interval: "1",
  days: 5,
  tf_minutes: 1,
  policy_json: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/options_buy_signal.rb [options]"
  opts.on("--exchange-segment SEG", "Exchange segment (e.g. IDX_I)") { |value| options[:exchange_segment] = value }
  opts.on("--symbol SYMBOL", "Instrument symbol (e.g. NIFTY)") { |value| options[:symbol] = value }
  opts.on("--interval INT", "Candle interval in minutes") { |value| options[:interval] = value }
  opts.on("--days N", Integer, "How many days back from today") { |value| options[:days] = value }
  opts.on("--tf-minutes N", Integer, "Strategy timeframe minutes") { |value| options[:tf_minutes] = value }
  opts.on("--policy-json PATH", "Path to calibrated policy JSON") { |value| options[:policy_json] = value }
end.parse!

api_data = DhanHqApiBars.new.fetch(
  exchange_segment: options[:exchange_segment],
  symbol: options[:symbol],
  interval: options[:interval],
  days: options[:days]
)
bars = api_data[:bars]
abort "No bars loaded" if bars.empty?

policy_config = if options[:policy_json]
                  parsed = JSON.parse(File.read(options[:policy_json]))
                  parsed["policy"] || {}
                else
                  {}
                end

signals = SuperTrendSignalGenerator.new(tf_minutes: options[:tf_minutes]).generate(bars).reject { |row| row[:warmup] }
latest = signals.last
policy = OptionsBuyingPolicy.new(config: policy_config).recommendation(
  signal: latest[:signal],
  adx: latest[:adx],
  atr_pct: latest[:atr_pct]
)

if policy[:decision] == :no_trade
  puts JSON.pretty_generate(policy.merge(latest_signal: latest[:signal], timestamp: latest[:timestamp]))
  exit 0
end

instrument = api_data[:instrument]
expiries = instrument.expiry_list
if expiries.empty?
  puts JSON.pretty_generate(decision: :no_trade, reason: "no option expiries available", symbol: instrument.display_name)
  exit 0
end

begin
  expiry, option_chain = expiries.lazy.map do |candidate_expiry|
    raw_chain = instrument.option_chain(expiry: candidate_expiry)
    chain = raw_chain[:oc] || raw_chain["oc"] || {}
    [candidate_expiry, chain]
  end.find { |_candidate_expiry, chain| !chain.empty? }
rescue StandardError => e
  puts JSON.pretty_generate(decision: :no_trade, reason: "option chain fetch failed", error: e.message)
  exit 0
end

if option_chain.nil? || option_chain.empty?
  puts JSON.pretty_generate(decision: :no_trade, reason: "option chain is empty for all expiries", symbol: instrument.display_name)
  exit 0
end

selector = LiveOptionSelector.new
selection = selector.select(
  option_chain: option_chain,
  side: policy[:side],
  moneyness: policy[:moneyness],
  spot_price: latest[:close]
)
if selection.nil?
  puts JSON.pretty_generate(
    decision: :no_trade,
    reason: "no liquid contract passed filters",
    side: policy[:side],
    moneyness: policy[:moneyness]
  )
  exit 0
end

payload = {
  decision: :buy_option,
  dry_run: true,
  instrument: {
    underlying_symbol: options[:symbol],
    underlying_security_id: instrument.security_id,
    underlying_exchange_segment: instrument.exchange_segment,
    expiry: expiry
  },
  signal_context: {
    signal: latest[:signal],
    timestamp: latest[:timestamp],
    close: latest[:close],
    adx: latest[:adx],
    atr_pct: latest[:atr_pct]
  },
  policy: policy,
  selected_contract: selection
}

puts JSON.pretty_generate(payload)

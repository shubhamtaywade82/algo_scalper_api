# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VwapReversalStrategy', type: :strategy_plugin do
  before { load_strategy_plugin('vwap-reversal') }

  let(:tz) { '+05:30' }
  let(:strategy) { VwapReversalStrategy.new(params: { slope_lookback: 17 }) }

  # A tradeable VWAP pullback needs three things at once: VWAP established BELOW the
  # pullback low (achieved by anchoring it with heavy-volume flat candles), a pullback deep
  # enough to drag RSI(14) back into the neutral 40-60 band, and a final confirming candle
  # that closes back above VWAP. With uniform volume VWAP sits near the move's mid-range and
  # any RSI-neutral pullback lands below it — hence the 5x-volume anchor candles.
  def uptrend_pullback_series
    prices = []
    5.times { prices << 24_000.0 } # heavy-volume flat anchor: pins VWAP near 24,000
    p = 24_000.0
    12.times do
      p += 10.0
      prices << p
    end
    3.times do
      p -= 36.0
      prices << p
    end
    prices << (p + 30.0) # final confirming bullish candle: closes back above VWAP

    candles = prices.each_with_index.map do |close, i|
      t = Time.zone.parse("2026-08-24 09:33:00 #{tz}") + (i * 3).minutes
      anchor_volume = i < 5 ? 500_000 : 100_000
      build_plugin_candle(t, open: close - 1.5, high: close + 1.0, low: close - 3.0, close: close, volume: anchor_volume)
    end
    build_plugin_series(candles, interval: '3')
  end

  # Mirror image of uptrend_pullback_series: heavy-volume flat candles anchor VWAP ABOVE
  # the rally high, the rally is deep enough to pull RSI(14) into the neutral band, and the
  # final candle closes back below VWAP.
  def downtrend_rally_series
    prices = []
    5.times { prices << 24_000.0 } # heavy-volume flat anchor: pins VWAP near 24,000
    p = 24_000.0
    12.times do
      p -= 10.0
      prices << p
    end
    3.times do
      p += 36.0
      prices << p
    end
    prices << (p - 30.0) # final confirming bearish candle: closes back below VWAP

    candles = prices.each_with_index.map do |close, i|
      t = Time.zone.parse("2026-08-24 09:33:00 #{tz}") + (i * 3).minutes
      anchor_volume = i < 5 ? 500_000 : 100_000
      build_plugin_candle(t, open: close + 1.5, high: close + 3.0, low: close - 1.0, close: close, volume: anchor_volume)
    end
    build_plugin_series(candles, interval: '3')
  end

  it 'buys CE on a pullback to VWAP with RSI in the neutral zone' do
    series = uptrend_pullback_series
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp, params: { slope_lookback: 17 }))

    expect(signal).to be_a(Signals::BuyCall)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    stop = rules[:stop_index_level]
    expect(stop).to be < close
    min_target = close + (1.5 * (close - stop))
    expect(rules[:target_index_level]).to be >= (min_target - 0.01)
    expect(rules[:giveback_enabled]).to be(false)
  end

  it 'buys PE on a rally to VWAP with RSI in the neutral zone' do
    series = downtrend_rally_series
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp, params: { slope_lookback: 17 }))

    expect(signal).to be_a(Signals::BuyPut)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    stop = rules[:stop_index_level]
    expect(stop).to be > close
    min_target = close - (1.5 * (stop - close))
    expect(rules[:target_index_level]).to be <= (min_target + 0.01)
  end

  it 'holds before the 09:30 entry window' do
    t = Time.zone.parse("2026-08-24 09:20:00 #{tz}")
    series = build_plugin_series([build_plugin_candle(t, open: 24_000, high: 24_005, low: 23_995, close: 24_000)], interval: '3')
    signal = strategy.call(build_plugin_context(series, cutoff: t))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('pre_session_window')
  end

  it 'holds during the 11:00-13:30 midday dead zone' do
    t = Time.zone.parse("2026-08-24 12:00:00 #{tz}")
    series = build_plugin_series([build_plugin_candle(t, open: 24_000, high: 24_005, low: 23_995, close: 24_000)], interval: '3')
    signal = strategy.call(build_plugin_context(series, cutoff: t))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('midday_dead_zone')
  end

  it 'holds when VWAP has no meaningful slope' do
    candles = (0..20).map do |i|
      t = Time.zone.parse("2026-08-24 09:33:00 #{tz}") + (i * 3).minutes
      build_plugin_candle(t, open: 24_000, high: 24_001, low: 23_999, close: 24_000, volume: 100_000)
    end
    series = build_plugin_series(candles, interval: '3')
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('flat_vwap')
  end
end

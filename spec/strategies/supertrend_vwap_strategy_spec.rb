# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SupertrendVwapStrategy', type: :strategy_plugin do
  before { load_strategy_plugin('supertrend-vwap') }

  let(:strategy) { SupertrendVwapStrategy.new(params: {}) }
  let(:tz) { '+05:30' }

  def series_from(prices, open_offset:, high_offset:, low_offset:)
    candles = prices.each_with_index.map do |close, i|
      t = Time.zone.parse("2026-08-24 09:15:00 #{tz}") + (i * 5).minutes
      build_plugin_candle(t, open: close + open_offset, high: close + high_offset, low: close + low_offset, close: close)
    end
    build_plugin_series(candles)
  end

  it 'buys CE when Supertrend is bullish and price is above VWAP' do
    prices = []
    p = 24_000.0
    40.times do
      p += 8.0
 prices << p
    end
    series = series_from(prices, open_offset: -2.0, high_offset: 3.0, low_offset: -5.0)

    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::BuyCall)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    expect(rules[:stop_index_level]).to be < close
    expect(rules[:target_index_level]).to be > close
    expect(rules[:giveback_enabled]).to be(false)
  end

  it 'buys PE when Supertrend is bearish and price is below VWAP' do
    prices = []
    p = 24_000.0
    40.times do
      p -= 8.0
 prices << p
    end
    series = series_from(prices, open_offset: 2.0, high_offset: 5.0, low_offset: -3.0)

    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::BuyPut)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    expect(rules[:stop_index_level]).to be > close
    expect(rules[:target_index_level]).to be < close
  end

  it 'holds when there is no candle data' do
    series = build_plugin_series([])
    signal = strategy.call(build_plugin_context(series, cutoff: Time.zone.now))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('no_candle_data')
  end
end

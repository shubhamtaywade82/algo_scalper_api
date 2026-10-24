# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OrbBreakoutStrategy', type: :strategy_plugin do
  before { load_strategy_plugin('orb-breakout') }

  let(:strategy) { OrbBreakoutStrategy.new(params: {}) }
  let(:tz) { '+05:30' }

  let(:prev_close_candle) do
    build_plugin_candle(Time.zone.parse("2026-08-21 15:10:00 #{tz}"), open: 24_000, high: 24_005, low: 23_995, close: 24_000)
  end

  # 09:15-09:40 (6 x 5m bars, range formed by 09:45): high 24050 / low 23950 -> width 100pts,
  # comfortably above the 0.20% min_range_pct floor at this price level.
  let(:range_candles) do
    (0..5).map do |i|
      t = Time.zone.parse("2026-08-24 09:15:00 #{tz}") + (i * 5).minutes
      build_plugin_candle(t, open: 24_000, high: 24_050, low: 23_950, close: 24_000)
    end
  end

  def series_for(*extra_candles)
    build_plugin_series([prev_close_candle] + range_candles + extra_candles)
  end

  it 'buys CE on a candle close above the opening range high' do
    breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_060, high: 24_110, low: 24_055, close: 24_100)
    signal = strategy.call(build_plugin_context(series_for(breakout), cutoff: breakout.timestamp))

    expect(signal).to be_a(Signals::BuyCall)
  end

  it 'sets an underlying-based stop/target/force-exit on the CE breakout' do
    breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_060, high: 24_110, low: 24_055, close: 24_100)
    signal = strategy.call(build_plugin_context(series_for(breakout), cutoff: breakout.timestamp))

    rules = signal.metadata[:exit_rules]
    expect(rules[:stop_index_level]).to eq(23_950.0)
    expect(rules[:target_index_level]).to eq(24_300.0) # 24100 + 2 * 100pt range
    expect(rules[:giveback_enabled]).to be(false)
    expect(rules[:force_exit_time].strftime('%H:%M')).to eq('14:30')
  end

  it 'buys PE on a candle close below the opening range low' do
    breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 23_940, high: 23_945, low: 23_880, close: 23_900)
    signal = strategy.call(build_plugin_context(series_for(breakout), cutoff: breakout.timestamp))

    expect(signal).to be_a(Signals::BuyPut)
    rules = signal.metadata[:exit_rules]
    expect(rules[:stop_index_level]).to eq(24_050.0)
    expect(rules[:target_index_level]).to eq(23_700.0) # 23900 - 2 * 100pt range
  end

  it 'holds while price is still inside the opening range' do
    inside = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_000, high: 24_020, low: 23_980, close: 24_010)
    signal = strategy.call(build_plugin_context(series_for(inside), cutoff: inside.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('inside_range')
  end

  it 'holds when the range is narrower than min_range_pct' do
    tight_range = (0..5).map do |i|
      t = Time.zone.parse("2026-08-24 09:15:00 #{tz}") + (i * 5).minutes
      build_plugin_candle(t, open: 24_000, high: 24_005, low: 23_995, close: 24_000)
    end
    breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_006, high: 24_010, low: 24_004, close: 24_008)
    series = build_plugin_series([prev_close_candle] + tight_range + [breakout])
    signal = strategy.call(build_plugin_context(series, cutoff: breakout.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('range_too_narrow')
  end

  it 'holds on a large opening gap' do
    gapped_prev_close = build_plugin_candle(Time.zone.parse("2026-08-21 15:10:00 #{tz}"), open: 24_000, high: 24_005, low: 23_995, close: 24_000)
    gapped_range = (0..5).map do |i|
      t = Time.zone.parse("2026-08-24 09:15:00 #{tz}") + (i * 5).minutes
      # ~3% gap up from prev close, well past the 0.8% max_gap_pct default
      build_plugin_candle(t, open: 24_720, high: 24_770, low: 24_670, close: 24_720)
    end
    breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_780, high: 24_830, low: 24_775, close: 24_820)
    series = build_plugin_series([gapped_prev_close] + gapped_range + [breakout])
    signal = strategy.call(build_plugin_context(series, cutoff: breakout.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('gap_too_large')
  end

  it 'suppresses a repeat signal once a direction has already resolved today' do
    first_breakout = build_plugin_candle(Time.zone.parse("2026-08-24 09:50:00 #{tz}"), open: 24_060, high: 24_110, low: 24_055, close: 24_100)
    later = build_plugin_candle(Time.zone.parse("2026-08-24 09:55:00 #{tz}"), open: 24_100, high: 24_150, low: 24_090, close: 24_140)
    series = series_for(first_breakout, later)
    signal = strategy.call(build_plugin_context(series, cutoff: later.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('already_resolved_today')
  end

  it 'holds while the opening range is still forming' do
    forming = build_plugin_candle(Time.zone.parse("2026-08-24 09:30:00 #{tz}"), open: 24_000, high: 24_010, low: 23_990, close: 24_005)
    series = build_plugin_series([prev_close_candle, range_candles.first, forming])
    signal = strategy.call(build_plugin_context(series, cutoff: forming.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('range_forming')
  end
end

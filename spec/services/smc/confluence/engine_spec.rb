# frozen_string_literal: true

# rubocop:disable Performance/TimesMap, Lint/AmbiguousOperatorPrecedence
require 'rails_helper'

RSpec.describe Smc::Confluence::Engine do
  def candle(hour_offset, open:, high:, low:, close:, volume: 100.0)
    t = Time.utc(2024, 6, 1, 6, 0, 0) + hour_offset.hours
    { timestamp: t.to_i, open: open, high: high, low: low, close: close, volume: volume }
  end

  describe '.run' do
    it 'returns an empty array for no candles' do
      expect(described_class.run([])).to eq([])
    end

    it 'emits one BarResult per candle' do
      candles = 25.times.map { |i| candle(i, open: 100, high: 101, low: 99, close: 100) }
      series = described_class.run(candles)
      expect(series.size).to eq(25)
      expect(series).to all(be_a(Smc::Confluence::BarResult))
    end

    it 'never fires signals when min_score is above the maximum possible score' do
      candles = 150.times.map do |i|
        candle(i, open: 100 + i * 0.02, high: 102 + i * 0.02, low: 98 + i * 0.02, close: 100 + i * 0.02)
      end
      cfg = Smc::Confluence::Configuration.new(min_score: 10)
      series = described_class.run(candles, configuration: cfg)
      expect(series.none?(&:long_signal)).to be(true)
      expect(series.none?(&:short_signal)).to be(true)
    end

    it 'marks a sell-side liquidity sweep and keeps recent_bull_sweep within swing*2 bars' do
      cfg = Smc::Confluence::Configuration.new(
        smc_swing: 3,
        liq_lookback: 5,
        liq_wick_pct: 0.1,
        ms_swing: 3,
        tl_pivot_len: 3,
        vp_bars: 10,
        min_score: 10
      )
      base = 100.0
      candles = []
      12.times do |i|
        candles << candle(i, open: base, high: base, low: base, close: base, volume: 50.0)
      end
      candles << candle(12, open: base, high: base, low: base - 6.0, close: base + 1.0, volume: 200.0)
      8.times do |i|
        candles << candle(13 + i, open: base, high: base + 1, low: base - 0.5, close: base, volume: 50.0)
      end

      series = described_class.run(candles, configuration: cfg)
      sweep_bar = series[12]
      expect(sweep_bar.liq_sweep_bull).to be(true)

      (13..18).each do |idx|
        expect(series[idx].recent_bull_sweep).to be(true), "expected recent sweep at bar #{idx}"
      end
      expect(series[19].recent_bull_sweep).to be(false)
    end

    it 'respects signal cooldown between long signals' do
      cfg = Smc::Confluence::Configuration.new(
        smc_swing: 3,
        ms_swing: 3,
        tl_pivot_len: 3,
        liq_lookback: 5,
        vp_bars: 8,
        min_score: 1,
        sig_cooldown: 5,
        ob_expire: 200
      )

      candles = []
      80.times do |i|
        o = 100.0 + Math.sin(i * 0.15) * 2
        candles << candle(i, open: o, high: o + 1.5, low: o - 1.5, close: o + 0.1, volume: 100 + i)
      end

      series = described_class.run(candles, configuration: cfg)
      long_idxs = series.each_index.select { |i| series[i].long_signal }
      if long_idxs.size >= 2
        gaps = long_idxs.each_cons(2).map { |a, b| b - a }
        expect(gaps.all? { |g| g >= cfg.sig_cooldown }).to be(true)
      end
    end

    it 'serializes the last bar to a JSON-ready hash' do
      candles = 30.times.map { |i| candle(i, open: 100, high: 101, low: 99, close: 100) }
      last = described_class.run(candles).last.serialize
      expect(last).to be_a(Hash)
      expect(last.keys).to include('long_score', 'short_score', 'choch_bull', 'structure_bias', 'pdh_sweep', 'pdl_sweep')
    end
  end
end
# rubocop:enable Performance/TimesMap, Lint/AmbiguousOperatorPrecedence

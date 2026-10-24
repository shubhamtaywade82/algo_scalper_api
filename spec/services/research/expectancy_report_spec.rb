# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::ExpectancyReport do
  def make_lifecycle(trend:, orb:, return_pct:, drawdown_pct:, minutes_to_peak:, phase_regime: {})
    regime = { 'trend' => trend, 'opening_range_breakout' => orb }.merge(phase_regime)
    Research::PremiumLifecycle.create!(
      underlying_symbol: 'NIFTY', expiry_flag: 'WEEK', option_type: 'CE', strike_label: 'ATM', interval: '5',
      entry_ts: Time.current + rand(10_000).seconds, status: 'computed',
      peak_return_pct: return_pct, max_drawdown_after_peak_pct: drawdown_pct, minutes_to_peak: minutes_to_peak,
      underlying_context: { 'entry' => { 'regime' => regime }, 'peak' => { 'regime' => {} } }
    )
  end

  describe '.call' do
    it 'groups lifecycles by the requested dimensions and computes avg return / win rate / avg drawdown' do
      make_lifecycle(trend: 'strong_bullish', orb: 'breakout_up', return_pct: 140.0, drawdown_pct: 20.0,
                     minutes_to_peak: 60)
      make_lifecycle(trend: 'strong_bullish', orb: 'breakout_up', return_pct: 100.0, drawdown_pct: 30.0,
                     minutes_to_peak: 80)
      make_lifecycle(trend: 'neutral', orb: 'inside_range', return_pct: -10.0, drawdown_pct: 40.0,
                     minutes_to_peak: 30)

      buckets = described_class.call(scope: Research::PremiumLifecycle.all, dimensions: %w[trend opening_range_breakout])

      expect(buckets.size).to eq(2)
      top = buckets.first
      expect(top[:context]).to eq('trend' => 'strong_bullish', 'opening_range_breakout' => 'breakout_up')
      expect(top[:sample_size]).to eq(2)
      expect(top[:avg_return_pct]).to eq(120.0)
      expect(top[:win_rate_pct]).to eq(100.0)
      expect(top[:avg_drawdown_pct]).to eq(25.0)
      expect(top[:avg_time_to_peak_minutes]).to eq(70.0)

      worst = buckets.last
      expect(worst[:context]).to eq('trend' => 'neutral', 'opening_range_breakout' => 'inside_range')
      expect(worst[:win_rate_pct]).to eq(0.0)
    end

    it 'ranks buckets by avg_return_pct descending' do
      make_lifecycle(trend: 'strong_bearish', orb: 'breakout_down', return_pct: 5.0, drawdown_pct: 10.0,
                     minutes_to_peak: 20)
      make_lifecycle(trend: 'strong_bullish', orb: 'breakout_up', return_pct: 200.0, drawdown_pct: 15.0,
                     minutes_to_peak: 40)

      buckets = described_class.call(scope: Research::PremiumLifecycle.all, dimensions: %w[trend opening_range_breakout])

      expect(buckets.map { |b| b[:context]['trend'] }).to eq(%w[strong_bullish strong_bearish])
    end

    it 'buckets lifecycles with no regime data as "unknown"' do
      Research::PremiumLifecycle.create!(
        underlying_symbol: 'NIFTY', expiry_flag: 'WEEK', option_type: 'CE', strike_label: 'ATM', interval: '5',
        entry_ts: Time.current, status: 'computed', peak_return_pct: 50.0, underlying_context: {}
      )

      buckets = described_class.call(scope: Research::PremiumLifecycle.all, dimensions: %w[trend])
      expect(buckets.size).to eq(1)
      expect(buckets.first[:context]['trend']).to eq('unknown')
      expect(buckets.first[:sample_size]).to eq(1)
    end

    it 'raises for unknown dimensions' do
      expect do
        described_class.call(scope: Research::PremiumLifecycle.all, dimensions: %w[not_a_real_dimension])
      end.to raise_error(ArgumentError, /unknown dimensions/)
    end

    it 'raises for an unsupported phase' do
      expect do
        described_class.call(scope: Research::PremiumLifecycle.all, phase: 'exit')
      end.to raise_error(ArgumentError, /phase must be/)
    end
  end
end

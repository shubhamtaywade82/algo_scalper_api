# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationConfigPatchBuilder do
  let(:combined_stats) do
    {
      avg_gain: 14.2,         # percentage points (e.g. 14.2%)
      avg_retrace_abs: 3.1,   # percentage points
      avg_loss_abs: 7.5,      # percentage points
      avg_oc: 4.2,
      sessions: { morning_oc: 2.1, midday_oc: 1.5, afternoon_oc: 0.6 }
    }
  end

  before do
    # Current config returns low values so all derived values will be >10% different
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        percentage_pnl_exit: { target_pct: 0.01 },
        trailing: { activation_pct: 0.01, drawdown_pct: 0.01 },
        profit_floor: { lock_pct: 0.01, trail_pct: 0.01 },
        institutional_trailing: {
          nifty: {
            trailing_distance: 0.01, early_trigger: 0.01,
            breakeven_trigger: 0.01, activation_trigger: 0.01
          },
          sensex: {
            trailing_distance: 0.01, early_trigger: 0.01,
            breakeven_trigger: 0.01, activation_trigger: 0.01
          }
        }
      }
    })
  end

  describe '.build' do
    subject(:patch) { described_class.build(combined_stats: combined_stats, symbol: 'NIFTY') }

    it 'returns a Hash with string keys' do
      expect(patch).to be_a(Hash)
      patch.each_key { |k| expect(k).to be_a(String) }
    end

    it 'derives target_pct as avg_gain * 0.45 / 100 clamped to 0.08..0.35' do
      # 14.2 * 0.45 / 100 = 0.0639
      # clamped to 0.08 (below minimum)
      expected = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      actual = patch.dig('risk', 'percentage_pnl_exit', 'target_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives trailing activation_pct as avg_gain * 0.25 / 100 clamped to 0.020..0.08' do
      # 14.2 * 0.25 / 100 = 0.0355
      expected = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      actual = patch.dig('risk', 'trailing', 'activation_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives trailing drawdown_pct as avg_retrace_abs * 0.80 / 100 clamped to 0.015..0.060' do
      # 3.1 * 0.8 / 100 = 0.0248
      expected = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      actual = patch.dig('risk', 'trailing', 'drawdown_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives institutional trailing_distance as drawdown_pct * 1.1 clamped to 0.030..0.12' do
      drawdown_pct = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      expected = [[drawdown_pct * 1.1, 0.030].max, 0.12].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'trailing_distance')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives early_trigger as activation_pct * 0.85 clamped to 0.020..0.06' do
      activation_pct = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      expected = [[activation_pct * 0.85, 0.020].max, 0.06].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'early_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives breakeven_trigger as activation_pct * 1.5 clamped to 0.040..0.12' do
      activation_pct = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      expected = [[activation_pct * 1.5, 0.040].max, 0.12].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'breakeven_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives activation_trigger as target_pct * 0.55 clamped to 0.08..0.20' do
      target_pct = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      expected = [[target_pct * 0.55, 0.08].max, 0.20].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'activation_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives profit_floor trail_pct as 1.0 - (avg_retrace_abs * 0.8 / 100) clamped to 0.55..0.92' do
      # 1.0 - (3.1 * 0.8 / 100) = 1.0 - 0.0248 = 0.9752 → clamped to 0.92
      expected = [[1.0 - (3.1 * 0.8 / 100.0), 0.55].max, 0.92].min
      actual = patch.dig('risk', 'profit_floor', 'trail_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'uses the correct symbol key for institutional_trailing' do
      sensex_patch = described_class.build(combined_stats: combined_stats, symbol: 'SENSEX')
      expect(sensex_patch.dig('risk', 'institutional_trailing')).to have_key('sensex')
      expect(sensex_patch.dig('risk', 'institutional_trailing')).not_to have_key('nifty')
    end
  end

  describe 'change filter (≥10% difference from current)' do
    it 'omits keys where proposed value is within 10% of current config' do
      # Set current config to closely match what the formulas would produce
      target = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          percentage_pnl_exit: { target_pct: target * 1.05 }, # only 5% off → omit
          trailing: { activation_pct: 0.01, drawdown_pct: 0.01 },
          profit_floor: { lock_pct: 0.01, trail_pct: 0.01 },
          institutional_trailing: { nifty: { trailing_distance: 0.01 } }
        }
      })

      patch = described_class.build(combined_stats: combined_stats, symbol: 'NIFTY')
      # target_pct should be absent since difference < 10%
      expect(patch.dig('risk', 'percentage_pnl_exit', 'target_pct')).to be_nil
    end

    it 'returns an empty hash if nothing changed by ≥10%' do
      target     = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      activation = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      drawdown   = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      distance   = [[drawdown * 1.1, 0.030].max, 0.12].min
      lock       = [[14.2 * 0.20 / 100.0, 0.06].max, 0.15].min
      trail      = [[1.0 - (3.1 * 0.8 / 100.0), 0.55].max, 0.92].min
      early      = [[activation * 0.85, 0.020].max, 0.06].min
      breakeven  = [[activation * 1.5, 0.040].max, 0.12].min
      act_trig   = [[target * 0.55, 0.08].max, 0.20].min

      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          percentage_pnl_exit: { target_pct: target },
          trailing: { activation_pct: activation, drawdown_pct: drawdown },
          profit_floor: { lock_pct: lock, trail_pct: trail },
          institutional_trailing: {
            nifty: {
              trailing_distance: distance, early_trigger: early,
              breakeven_trigger: breakeven, activation_trigger: act_trig
            }
          }
        }
      })

      patch = described_class.build(combined_stats: combined_stats, symbol: 'NIFTY')
      expect(patch).to eq({})
    end
  end
end

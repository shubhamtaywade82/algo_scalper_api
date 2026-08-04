# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationConfigPatchBuilder do
  describe '.build' do
    let(:combined_stats) do
      { avg_gain: 14.2, avg_retrace_abs: 3.1 }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: {
          percentage_pnl_exit: { target_pct: 0.10 },
          trailing: { activation_pct: 0.03, drawdown_pct: 0.02 },
          profit_floor: { lock_pct: 0.08, trail_pct: 0.70 },
          institutional_trailing: {
            nifty: {
              trailing_distance: 0.05,
              early_trigger: 0.03,
              breakeven_trigger: 0.06,
              activation_trigger: 0.12
            }
          }
        }
      )
    end

    it 'emits risk keys derived from stats' do
      patch = described_class.build(combined_stats: combined_stats, symbol: 'NIFTY')

      expect(patch.dig('risk', 'trailing', 'activation_pct')).to be_a(Numeric)
      expect(patch.dig('risk', 'institutional_trailing', 'nifty', 'trailing_distance')).to be_a(Numeric)
    end
  end

  describe '.from_trailing_params' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: {
          institutional_trailing: {
            nifty: {
              early_trigger: 0.03,
              breakeven_trigger: 0.08,
              activation_trigger: 0.15,
              trailing_distance: 0.20
            }
          }
        }
      )
    end

    it 'wraps trailing params under institutional_trailing' do
      patch = described_class.from_trailing_params(
        symbol: 'NIFTY',
        params: {
          early_trigger: 0.05,
          breakeven_trigger: 0.10,
          activation_trigger: 0.20,
          trailing_distance: 0.25
        }
      )

      expect(patch.dig('risk', 'institutional_trailing', 'nifty', 'early_trigger')).to eq(0.05)
    end
  end
end

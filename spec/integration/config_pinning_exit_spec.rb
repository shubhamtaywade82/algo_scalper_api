# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Config pinning on exit path' do
  before do
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
  end

  describe 'adaptive trail hard stop uses pinned config snapshot' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 1,
        active?: true,
        entry_price: 100.0,
        quantity: 1,
        meta: {
          'direction' => 'bullish',
          'config_snapshot' => {
            'risk' => {
              'adaptive_trailing' => {
                'enabled' => true,
                'stages' => [{ 'min_profit' => 0.0, 'trail_behind_peak' => 0.40, 'hard_stop' => -0.20 }]
              }
            }
          }
        },
        instrument: nil,
        watchable: nil,
        index_key: 'NIFTY',
        high_water_mark_pnl: 0.0,
        current_pnl_pct: -0.25
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: {
          adaptive_trailing: {
            enabled: true,
            stages: [{ min_profit: 0.0, trail_behind_peak: 0.40, hard_stop: -0.99 }]
          }
        }
      )
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: -0.25, ltp: 75.0, pnl: -25.0, hwm_pnl: 0.0 }
      )
    end

    it 'fires at pinned -20% hard stop rather than live -99%' do
      result = Live::UnifiedExitChecker.check_exit_conditions(tracker)

      expect(result).not_to be_nil
      expect(result[:reason]).to eq('ADAPTIVE_TRAIL_HARD_STOP')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Config pinning on exit path' do
  # HISTORY: this spec used to assert that the exit path consulted a
  # config_snapshot pinned on the tracker at entry, so a mid-position config
  # change could never move an open stop. That pinning was removed from the
  # exit path in the "Remove unused guards and rules" refactor (the resolver
  # now only serves the AI dynamic-config agent). This spec pins the CURRENT
  # contract instead: the exit path reads the live (30s-memoized) config, and
  # a tracker-level config_snapshot is NOT consulted.
  describe 'exit path reads the live config, not a tracker-pinned snapshot' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 1,
        active?: true,
        entry_price: 100.0,
        quantity: 1,
        symbol: 'NIFTY24MAR22000CE',
        meta: {
          'direction' => 'bullish',
          'config_snapshot' => {
            'risk' => {
              'adaptive_trailing' => {
                'enabled' => true,
                'stages' => [{ 'min_profit' => 0.0, 'trail_behind_peak' => 0.40, 'hard_stop' => -0.50 }]
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
      Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
      Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
    end

    it 'evaluates against the live stop-loss config regardless of the pinned snapshot' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { sl_pct: 0.30 }
      )
      # -35% breaches the LIVE stop (30%) but NOT the pinned snapshot's own
      # hard_stop (-50%): only a path reading the live config can exit here.
      # (The inverse fixture — pinned tighter than live — would exit either way
      # and prove nothing.)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: -0.35, ltp: 65.0, pnl: -35.0, hwm_pnl: 0.0 }
      )

      result = Live::UnifiedExitChecker.check_exit_conditions(tracker)

      expect(result).not_to be_nil
      expect(result[:reason]).to eq('STOP_LOSS')
      expect(result[:path]).to eq('stop_loss')
    end
  end
end

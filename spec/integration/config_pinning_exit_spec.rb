# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Config pinning on exit path' do
  before do
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
  end

  describe 'loss_limit_hit?' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        meta: {
          'config_snapshot' => {
            'risk' => { 'sl_pct' => 0.08 },
            'exit' => { 'stop_loss' => { 'type' => 'static', 'value' => 0.08 } }
          }
        },
        instrument: nil,
        watchable: nil
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { sl_pct: 0.50 },
        exit: { stop_loss: { type: 'static', value: 0.50 } }
      )
    end

    it 'uses pinned stop loss when live config differs' do
      snapshot = { pnl_pct: -0.09 }

      expect(Live::UnifiedExitChecker.loss_limit_hit?(tracker, snapshot)).to be(true)
    end

    it 'does not fire when loss is below pinned stop' do
      snapshot = { pnl_pct: -0.05 }

      expect(Live::UnifiedExitChecker.loss_limit_hit?(tracker, snapshot)).to be(false)
    end
  end
end

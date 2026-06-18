# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnifiedExitChecker do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      active?: true,
      entry_price: 100.0,
      quantity: 10,
      meta: {},
      instrument: nil,
      watchable: nil
    )
  end

  before do
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: { sl_pct: 0.12, tp_pct: 0.50 },
      exit: { stop_loss: { type: 'static', value: 0.12 }, take_profit: 0.50 }
    )
  end

  describe '.check_exit_conditions' do
    it 'returns nil when pnl snapshot is missing' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)

      expect(described_class.check_exit_conditions(tracker)).to be_nil
    end

    it 'returns stop loss exit when loss exceeds threshold' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: -0.15, ltp: 85.0, pnl: -150.0, hwm_pnl: 0.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('STOP_LOSS')
      expect(result[:path]).to eq('stop_loss')
    end

    it 'returns take profit exit when gain exceeds threshold' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 0.55, ltp: 155.0, pnl: 550.0, hwm_pnl: 550.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('TAKE_PROFIT')
      expect(result[:path]).to eq('take_profit')
    end

    it 'returns nil when pnl is inside stop and take profit bands' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 0.05, ltp: 105.0, pnl: 50.0, hwm_pnl: 50.0 }
      )

      expect(described_class.check_exit_conditions(tracker)).to be_nil
    end
  end

  describe '.loss_limit_hit?' do
    it 'uses pinned stop loss from tracker config snapshot' do
      pinned_tracker = instance_double(
        PositionTracker,
        id: 2,
        meta: {
          'config_snapshot' => {
            'risk' => { 'sl_pct' => 0.08 },
            'exit' => { 'stop_loss' => { 'type' => 'static', 'value' => 0.08 } }
          }
        },
        instrument: nil,
        watchable: nil
      )
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { sl_pct: 0.50 },
        exit: { stop_loss: { type: 'static', value: 0.50 } }
      )

      expect(described_class.loss_limit_hit?(pinned_tracker, { pnl_pct: -0.09 })).to be(true)
      expect(described_class.loss_limit_hit?(pinned_tracker, { pnl_pct: -0.05 })).to be(false)
    end
  end
end

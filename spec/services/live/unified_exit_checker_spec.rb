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
      meta: { 'direction' => 'bullish' },
      instrument: nil,
      watchable: nil
    )
  end

  before do
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        adaptive_trailing: {
          enabled: true,
          supertrend_flip_exit: false,
          counter_candles: 0
        }
      }
    )
  end

  describe '.check_exit_conditions' do
    it 'returns nil when pnl snapshot is missing' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)

      expect(described_class.check_exit_conditions(tracker)).to be_nil
    end

    it 'returns adaptive hard stop when loss exceeds entry guard floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: -0.31, ltp: 69.0, pnl: -310.0, hwm_pnl: 0.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('ADAPTIVE_TRAIL_HARD_STOP')
      expect(result[:path]).to eq('adaptive_trail')
    end

    it 'returns adaptive trail exit when giveback exceeds stage floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 1.10, ltp: 210.0, pnl: 1100.0, hwm_pnl: 2000.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('ADAPTIVE_TRAIL')
      expect(result[:path]).to eq('adaptive_trail')
    end

    it 'returns nil when price remains above the trail floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 0.05, ltp: 105.0, pnl: 50.0, hwm_pnl: 50.0 }
      )

      expect(described_class.check_exit_conditions(tracker)).to be_nil
    end
  end
end

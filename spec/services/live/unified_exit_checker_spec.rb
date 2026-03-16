# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnifiedExitChecker do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      active?: true,
      entry_price: 200.0,
      quantity: 50,
      high_water_mark_pnl: 0.0,
      current_pnl_pct: 0.0,
      meta: {},
      order_no: 'ORD-1'
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: {
          emergency_peak_loss_exit: true,
          emergency_min_peak_pct: 0.10
        }
      },
      risk: {},
      indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }]
    })
  end

  describe 'emergency peak-loss exit' do
    it 'triggers when peak >= 10% and current < -2%' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0) # 1500 / (200*50) = 15%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)      # -5%

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be true
    end

    it 'does not trigger when peak < 10%' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(500.0)  # 500 / 10000 = 5%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when current loss is shallow (> -2%)' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0) # 15%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.01)      # -1% (above -2% threshold)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when disabled in config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: false }
        },
        risk: {},
        indices: []
      })
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0)
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'handles zero entry value gracefully' do
      allow(tracker).to receive(:entry_price).and_return(0.0)
      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end
  end

  describe 'structure invalidation' do
    it 'triggers exit for long_pe when underlying rises above invalidation price' do
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_pe',
        'structure_invalidation_price' => 23800.0,
        'index_key' => 'NIFTY'
      })
      tick = double(ltp: 23850.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      result = described_class.send(:structure_invalidated?, tracker, 23850.0, 23800.0)
      expect(result).to be true
    end

    it 'triggers exit for long_ce when underlying falls below invalidation price' do
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_ce',
        'structure_invalidation_price' => 23800.0,
        'index_key' => 'NIFTY'
      })

      result = described_class.send(:structure_invalidated?, tracker, 23750.0, 23800.0)
      expect(result).to be true
    end

    it 'does not trigger for long_pe when underlying is below invalidation' do
      allow(tracker).to receive(:meta).and_return({ 'direction' => 'long_pe' })
      result = described_class.send(:structure_invalidated?, tracker, 23750.0, 23800.0)
      expect(result).to be false
    end

    it 'does not trigger for unknown direction' do
      allow(tracker).to receive(:meta).and_return({ 'direction' => 'unknown' })
      result = described_class.send(:structure_invalidated?, tracker, 23850.0, 23800.0)
      expect(result).to be false
    end

    it 'returns nil gracefully when TickQuery fails' do
      allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError)
      result = described_class.send(:resolve_underlying_ltp, 'NIFTY')
      expect(result).to be_nil
    end

    it 'skips structure invalidation when invalidation_price is nil in meta' do
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_pe',
        'index_key' => 'NIFTY'
      })
      expect(Live::TickQuery).not_to receive(:for_security)
    end
  end
end

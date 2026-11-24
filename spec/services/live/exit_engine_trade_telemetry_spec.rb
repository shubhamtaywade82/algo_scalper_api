# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ExitEngine do
  let(:router) { instance_double(TradingSystem::OrderRouter) }
  let(:engine) { described_class.new(order_router: router) }

  describe '#resolved_entry_tf' do
    it 'defaults to 1m when metadata has no entry_tf' do
      tracker = instance_double(PositionTracker, entry_tf: nil, meta: {})
      expect(engine.send(:resolved_entry_tf, tracker)).to eq('1m')
    end
  end

  describe '#record_trade_telemetry' do
    it 'records telemetry from meta when the column-backed risk value is nil' do
      tracker = create(:position_tracker, :exited, index_key: 'NIFTY', last_pnl_rupees: -1000, high_water_mark_pnl: 500,
                                                   meta: { 'entry_risk_rupees' => 2000, 'bos_age_at_entry' => 3 })

      engine.send(:record_trade_telemetry, tracker, 100.0, 'STOP_LOSS')

      telemetry = TradeTelemetry.find_by!(tracker_id: tracker.id)
      expect(telemetry.exit_r).to eq(-0.5)
      expect(telemetry.max_r_reached).to eq(0.25)
      expect(telemetry.bos_age_at_entry).to eq(3)
    end

    it 'skips telemetry when no entry risk is known anywhere' do
      tracker = create(:position_tracker, :exited, meta: {})

      expect { engine.send(:record_trade_telemetry, tracker, 100.0, 'STOP_LOSS') }
        .not_to change(TradeTelemetry, :count)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TrailingStopRule do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: 100.0
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      current_ltp: 110.0,
      pnl: 1000.0,
      pnl_pct: 10.0,
      high_water_mark: 1200.0
    )
  end
  let(:risk_config) { { exit_drop_pct: 10.0 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when trailing stop is triggered' do
      it 'returns exit result when HWM drop exceeds threshold' do
        # HWM: 1200, PnL: 1000, Drop: (1200-1000)/1200 = 16.67% >= 10%
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TRAILING STOP')
        expect(result.metadata[:pnl]).to eq(1000.0)
        expect(result.metadata[:hwm]).to eq(1200.0)
        expect(result.metadata[:drop_pct]).to be >= 0.10
      end

      it 'triggers exit when drop exactly equals threshold' do
        position_data.pnl = 1080.0 # Drop: (1200-1080)/1200 = 10%
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when trailing stop is not triggered' do
      it 'returns no_action when drop is below threshold' do
        position_data.pnl = 1150.0 # Drop: (1200-1150)/1200 = 4.17% < 10%
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when data is missing' do
      it 'returns skip_result when pnl is nil' do
        position_data.pnl = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when hwm is nil' do
        position_data.high_water_mark = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when hwm is zero' do
        position_data.high_water_mark = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when threshold is zero' do
      it 'returns skip_result when exit_drop_pct is 0' do
        risk_config[:exit_drop_pct] = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 50' do
        expect(described_class::PRIORITY).to eq(50)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TimeBasedExitRule do
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
    Positions::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      current_ltp: 103.0,
      pnl: 300.0,
      pnl_pct: 0.03
    )
  end
  let(:exit_time) { Time.zone.parse('15:20') }
  let(:risk_config) do
    {
      exit: { time_based: { enabled: true, exit_time: '15:20' } }
    }
  end
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      current_time: exit_time
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when exit time is reached' do
      before do
        allow(Live::UnifiedExitChecker).to receive(:time_based_exit?).and_return(true)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TIME_BASED')
      end
    end

    context 'when exit time is not reached' do
      before do
        allow(Live::UnifiedExitChecker).to receive(:time_based_exit?).and_return(false)
      end

      it 'returns no_action' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when exit time is not configured' do
      it 'is disabled' do
        plain_context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: {}
        )
        result = described_class.new(config: {}).enabled?(plain_context)
        expect(result).to be false
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 40' do
        expect(described_class::PRIORITY).to eq(40)
      end
    end
  end
end

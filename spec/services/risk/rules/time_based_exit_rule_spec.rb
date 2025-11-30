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
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      current_ltp: 103.0,
      pnl: 300.0,
      pnl_pct: 3.0
    )
  end
  let(:exit_time) { Time.zone.parse('15:20') }
  let(:risk_config) do
    {
      time_exit_hhmm: '15:20',
      min_profit_rupees: 200.0
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
    context 'when exit time is reached and minimum profit is met' do
      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('time-based exit')
        expect(result.reason).to include('15:20')
        expect(result.metadata[:exit_time]).to eq(exit_time)
        expect(result.metadata[:pnl_rupees]).to eq(300.0)
      end
    end

    context 'when exit time is reached but minimum profit not met' do
      before do
        position_data.pnl = 100.0
      end

      it 'returns no_action' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when exit time is not reached' do
      before do
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          current_time: exit_time - 1.hour
        )
        @context = context
      end

      it 'returns no_action' do
        result = rule.evaluate(@context)
        expect(result.no_action?).to be true
      end
    end

    context 'when current time is after market close' do
      before do
        risk_config[:market_close_hhmm] = '15:30'
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          current_time: Time.zone.parse('15:35')
        )
        @context = context
      end

      it 'returns no_action' do
        result = rule.evaluate(@context)
        expect(result.no_action?).to be true
      end
    end

    context 'when exit time is not configured' do
      before do
        risk_config.delete(:time_exit_hhmm)
      end

      it 'returns skip_result' do
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when minimum profit is zero' do
      before do
        risk_config[:min_profit_rupees] = 0
      end

      it 'exits without profit check' do
        position_data.pnl = 50.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when profit is negative' do
      before do
        position_data.pnl = -100.0
      end

      it 'returns no_action even if time reached' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 40' do
        expect(described_class::PRIORITY).to eq(40)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::SessionEndRule do
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
      pnl: 100.0,
      pnl_pct: 10.0
    )
  end
  let(:risk_config) { {} }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when session is ending' do
      before do
        allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
          { should_exit: true, reason: 'session_end' }
        )
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('session end')
        expect(result.metadata[:session_check][:should_exit]).to be true
      end
    end

    context 'when session is not ending' do
      before do
        allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
          { should_exit: false }
        )
      end

      it 'returns no_action' do
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

    describe 'priority' do
      it 'has priority 10 (highest)' do
        expect(described_class::PRIORITY).to eq(10)
      end
    end
  end
end

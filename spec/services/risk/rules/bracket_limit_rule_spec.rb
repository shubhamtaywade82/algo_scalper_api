# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::BracketLimitRule do
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
      current_ltp: 105.0,
      pnl: 50.0,
      pnl_pct: 5.0,
      sl_price: 98.0,
      tp_price: 107.0
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
    context 'when stop loss is hit' do
      before do
        allow(position_data).to receive(:sl_hit?).and_return(true)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
        expect(result.metadata[:limit_type]).to eq('stop_loss')
      end
    end

    context 'when take profit is hit' do
      before do
        allow(position_data).to receive(:tp_hit?).and_return(true)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TP HIT')
        expect(result.metadata[:limit_type]).to eq('take_profit')
      end
    end

    context 'when neither SL nor TP is hit' do
      before do
        allow(position_data).to receive_messages(sl_hit?: false, tp_hit?: false)
      end

      it 'returns no_action' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when current LTP is missing' do
      before do
        position_data.current_ltp = nil
      end

      it 'returns skip_result' do
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when current LTP is zero' do
      before do
        position_data.current_ltp = 0
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

    describe 'priority' do
      it 'has priority 25' do
        expect(described_class::PRIORITY).to eq(25)
      end
    end
  end
end

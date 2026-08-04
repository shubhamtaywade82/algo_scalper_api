# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::GreenTradeCapRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:tracker) { instance_double(PositionTracker, order_no: 'ORD001', high_water_mark_pnl: 1_131.0) }
  let(:snapshot) do
    {
      ltp: 85.0,
      pnl: -3_677.0,
      pnl_pct: -0.149,
      hwm_pnl: 1_131.0
    }
  end
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      pnl_pct: snapshot[:pnl_pct],
      pnl_rupees: snapshot[:pnl],
      high_water_mark: snapshot[:hwm_pnl],
      tracker: tracker,
      tracker_snapshot: snapshot
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        green_trade_cap: {
          enabled: true,
          min_hwm_rupees: 300,
          max_adverse_pct: 0.08
        }
      }
    )
  end

  describe '#evaluate' do
    context 'when trade was green and breaches adverse cap' do
      it 'exits before full premium SL' do
        result = rule.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('GREEN_TRADE_CAP')
      end
    end

    context 'when loss is within cap' do
      it 'returns no_action' do
        allow(context).to receive(:pnl_pct).and_return(-0.05)
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when HWM never reached minimum' do
      it 'returns no_action' do
        allow(context).to receive_messages(high_water_mark: 100.0, tracker_snapshot: snapshot.merge(hwm_pnl: 100.0))
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end
  end
end

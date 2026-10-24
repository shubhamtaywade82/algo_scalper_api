# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::ZeroHwmFalseEntryRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:tracker) { instance_double(PositionTracker, order_no: 'ORD001', high_water_mark_pnl: 0.0, entry_price: 100.0, created_at: created_at) }
  let(:created_at) { 3.minutes.ago }
  let(:snapshot) { { hwm_pnl: 0.0 } }
  let(:risk_config) do
    { zero_hwm_false_entry: { enabled: true, min_hold_seconds: 120, hwm_threshold_rupees: 0 } }
  end
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      current_ltp: 95.0,
      tracker: tracker,
      tracker_snapshot: snapshot,
      high_water_mark: 0.0,
      risk_config: risk_config
    )
  end

  describe '#evaluate' do
    context 'when position never went green past the grace period' do
      it 'exits' do
        result = rule.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('ZERO_HWM_FALSE_ENTRY')
      end
    end

    context 'when still within the grace period' do
      let(:created_at) { 30.seconds.ago }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when the position did go green' do
      let(:snapshot) { { hwm_pnl: 250.0 } }

      before { allow(context).to receive(:high_water_mark).and_return(250.0) }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when disabled via config' do
      let(:risk_config) { { zero_hwm_false_entry: { enabled: false } } }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when position is not active' do
      it 'returns skip_result' do
        allow(context).to receive(:active?).and_return(false)
        result = rule.evaluate(context)

        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 15' do
        expect(described_class::PRIORITY).to eq(15)
      end
    end
  end
end

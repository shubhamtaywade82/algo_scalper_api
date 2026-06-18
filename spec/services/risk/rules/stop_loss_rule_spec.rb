# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::StopLossRule do
  let(:tracker) { instance_double(PositionTracker, active?: active, id: 1) }
  let(:active) { true }
  let(:tracker_snapshot) { { pnl_pct: -0.04, ltp: 96.0, pnl: -40.0, hwm_pnl: 0.0 } }
  let(:position) { OpenStruct.new(pnl_pct: -0.04) }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      tracker_snapshot: tracker_snapshot,
      risk_config: { sl_pct: 0.02 }
    )
  end
  let(:rule) { described_class.new(config: { sl_pct: 0.02 }) }

  describe '#evaluate' do
    it 'returns exit result when loss limit is hit' do
      allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).with(tracker, tracker_snapshot).and_return(true)

      result = rule.evaluate(context)

      expect(result).to be_exit
      expect(result.reason).to eq('STOP_LOSS')
      expect(result.metadata[:path]).to eq('stop_loss')
      expect(result.metadata[:pnl_pct]).to eq(-4.0)
    end

    it 'returns no_action when loss limit is not hit' do
      allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).with(tracker, tracker_snapshot).and_return(false)

      expect(rule.evaluate(context)).to be_no_action
    end

    it 'returns skip_result when position is not active' do
      allow(tracker).to receive(:active?).and_return(false)

      expect(rule.evaluate(context)).to be_skip
    end
  end

  describe 'priority' do
    it 'has priority 20' do
      expect(described_class::PRIORITY).to eq(20)
    end
  end
end

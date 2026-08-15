# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::MaxPremiumLossRule do
  let(:rule) { described_class.new(config: {}) }
  let(:tracker) { instance_double(PositionTracker, short_position?: short_position, premium_received: premium_received, quantity: 1) }
  let(:short_position) { true }
  let(:premium_received) { 100.0 }
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      tracker: tracker,
      current_ltp: current_ltp
    )
  end

  before do
    allow(context).to receive(:config_value) { |_key, default| default }
  end

  describe '#evaluate' do
    context 'when a long position' do
      let(:short_position) { false }
      let(:current_ltp) { 500.0 }

      it 'returns no_action_result regardless of loss' do
        expect(rule.evaluate(context).exit?).to be false
      end
    end

    context 'when loss is within the default 2x cap' do
      let(:current_ltp) { 250.0 } # loss = 150, cap = 200

      it 'returns no_action_result' do
        expect(rule.evaluate(context).exit?).to be false
      end
    end

    context 'when loss exceeds the default 2x cap' do
      let(:current_ltp) { 350.0 } # loss = 250, cap = 200

      it 'returns exit_result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('MAX_PREMIUM_LOSS')
      end
    end

    context 'when quantity > 1 (premium_received is a total, current_ltp is per-unit)' do
      let(:tracker) { instance_double(PositionTracker, short_position?: true, premium_received: 7500.0, quantity: 75) }
      let(:current_ltp) { 150.0 } # satisfies the outer `context` let/before hook; unused directly
      let(:multi_unit_context) do
        ctx = instance_double(Risk::Rules::RuleContext, active?: true, tracker: tracker, current_ltp: 150.0)
        allow(ctx).to receive(:config_value) { |_key, default| default }
        ctx
      end

      it 'compares per-unit values, not total-vs-per-unit' do
        # per-unit received = 7500/75 = 100; ltp 150 is a loss of 50, well under the 2x (200) cap.
        # Comparing total-vs-per-unit would (wrongly) read ltp as a huge negative loss and fire immediately.
        expect(rule.evaluate(multi_unit_context).exit?).to be false
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::FastProfitLockRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      peak_profit_pct: peak_profit_pct,
      pnl_pct: current_pnl_pct
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(risk: { fast_profit_lock: { enabled: true } })
  end

  describe '#evaluate' do
    context 'when peak touched a tier and price gave back below its lock floor' do
      let(:peak_profit_pct) { 0.08 }
      let(:current_pnl_pct) { 0.03 }

      it 'exits at the tier floor' do
        result = rule.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('FAST_PROFIT_LOCK')
        expect(result.metadata[:tier_lock_pct]).to eq(0.045)
      end
    end

    context 'when still above the touched tier floor' do
      let(:peak_profit_pct) { 0.08 }
      let(:current_pnl_pct) { 0.06 }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when peak never touched the first tier' do
      let(:peak_profit_pct) { 0.03 }
      let(:current_pnl_pct) { 0.01 }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when disabled via config' do
      let(:peak_profit_pct) { 0.08 }
      let(:current_pnl_pct) { 0.03 }

      before { allow(AlgoConfig).to receive(:fetch).and_return(risk: { fast_profit_lock: { enabled: false } }) }

      it 'returns skip_result' do
        result = rule.evaluate(context)

        expect(result.skip?).to be true
      end
    end

    context 'when position is not active' do
      let(:peak_profit_pct) { 0.08 }
      let(:current_pnl_pct) { 0.03 }

      it 'returns skip_result' do
        allow(context).to receive(:active?).and_return(false)
        result = rule.evaluate(context)

        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 33' do
        expect(described_class::PRIORITY).to eq(33)
      end
    end
  end
end

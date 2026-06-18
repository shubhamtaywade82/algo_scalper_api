# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::AdaptiveTrailRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      active?: true,
      id: 42,
      entry_price: BigDecimal('100'),
      quantity: 1,
      meta: { 'direction' => 'bullish' },
      instrument: nil,
      watchable: nil
    )
  end
  let(:position) { OpenStruct.new(current_ltp: current_ltp, pnl_pct: 0.0) }
  let(:snapshot) { { hwm_pnl: hwm_pnl } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      tracker_snapshot: snapshot,
      risk_config: { adaptive_trailing: { supertrend_flip_exit: false, counter_candles: 0 } }
    )
  end

  describe '#evaluate' do
    context 'when the entry guard hard stop is hit before momentum confirms' do
      let(:current_ltp) { BigDecimal('69') }
      let(:hwm_pnl) { 10.0 }

      it 'exits at the hard stop' do
        result = described_class.new(config: context.risk_config).evaluate(context)

        expect(result).to be_exit
        expect(result.reason).to eq('ADAPTIVE_TRAIL_HARD_STOP')
        expect(result.metadata[:stage]).to eq('entry_guard')
      end
    end

    context 'when runner mode gives back more than the configured floor' do
      let(:current_ltp) { BigDecimal('210') }
      let(:hwm_pnl) { 200.0 }

      it 'exits with runner-mode trail metadata' do
        result = described_class.new(config: context.risk_config).evaluate(context)

        expect(result).to be_exit
        expect(result.reason).to eq('ADAPTIVE_TRAIL')
        expect(result.metadata[:stage]).to eq('runner_mode')
        expect(result.metadata[:trail_price]).to eq(256.0)
      end
    end

    context 'when price remains above the trail floor' do
      let(:current_ltp) { BigDecimal('280') }
      let(:hwm_pnl) { 200.0 }

      it 'does not exit' do
        result = described_class.new(config: context.risk_config).evaluate(context)

        expect(result).to be_no_action
      end
    end
  end
end

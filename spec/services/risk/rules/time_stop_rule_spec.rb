# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TimeStopRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      active?: true,
      created_at: 10.minutes.ago,
      entry_strategy: 'alpha_scalp',
      entry_path: 'scalp',
      meta: {},
      index_key: 'NIFTY',
      instrument: nil,
      watchable: nil
    )
  end

  let(:position) { OpenStruct.new(pnl: 0.0, pnl_pct: 0.0) }

  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      risk_config: {
        time_stop: {
          enabled: true,
          scalp: { max_minutes: 8, max_candles: 8 },
          trend: { NIFTY: 20 }
        }
      }
    )
  end

  let(:rule) { described_class.new(config: {}) }

  describe '#evaluate' do
    context 'when scalp trade exceeds time limit' do
      it 'triggers a time stop exit' do
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to include('TIME_STOP')
        expect(result.metadata[:trade_type]).to eq(:scalp)
        expect(result.metadata[:time_limit]).to eq(8.0)
      end
    end

    context 'when scalp trade is within time limit' do
      it 'does not exit' do
        allow(tracker).to receive(:created_at).and_return(1.minute.ago)
        result = rule.evaluate(context)
        expect(result).to be_no_action
      end
    end

    context 'when trend trade is within time limit' do
      before do
        allow(tracker).to receive_messages(
          entry_strategy: 'trend_buying',
          entry_path: 'trend'
        )
      end

      it 'does not exit' do
        result = rule.evaluate(context)
        expect(result).to be_no_action
      end

      it 'triggers a time stop exit when limit is exceeded' do
        allow(tracker).to receive(:created_at).and_return(25.minutes.ago)
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to include('TIME_STOP')
        expect(result.metadata[:trade_type]).to eq(:trend)
        expect(result.metadata[:time_limit]).to eq(20)
      end
    end

    context 'when trade is strongly in profit' do
      before do
        allow(tracker).to receive_messages(
          entry_strategy: 'trend_buying',
          entry_path: 'trend',
          created_at: 25.minutes.ago
        )
        allow(position).to receive(:pnl_pct).and_return(0.06)
      end

      it 'bypasses the time stop to let winners run' do
        result = rule.evaluate(context)
        expect(result).to be_skip
      end
    end

    context 'when risk config has no time_stop section' do
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position,
          tracker: tracker,
          risk_config: {}
        )
      end

      it 'falls back to default limits' do
        allow(tracker).to receive(:created_at).and_return(20.minutes.ago)
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.metadata[:time_limit]).to eq(15.0)
      end
    end
  end
end
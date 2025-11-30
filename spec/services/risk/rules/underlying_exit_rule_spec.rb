# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::UnderlyingExitRule do
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
      position_direction: 'bullish'
    )
  end
  let(:risk_config) do
    {
      underlying_trend_score_threshold: 10.0,
      underlying_atr_collapse_multiplier: 0.65
    }
  end
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      feature_flags: { enable_underlying_aware_exits: true }
    )
  end

  describe '#evaluate' do
    context 'when underlying exits are disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(feature_flags: {})
      end

      it 'returns skip_result' do
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when structure break against position' do
      let(:underlying_state) do
        instance_double(
          'UnderlyingState',
          bos_state: :broken,
          bos_direction: :bearish,
          trend_score: 15.0,
          atr_trend: :rising,
          atr_ratio: 0.8
        )
      end

      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(underlying_state)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('underlying_structure_break')
        expect(result.metadata[:position_direction]).to eq(:bullish)
      end
    end

    context 'when trend is weak' do
      let(:underlying_state) do
        instance_double(
          'UnderlyingState',
          bos_state: :intact,
          trend_score: 8.0,
          atr_trend: :rising,
          atr_ratio: 0.8
        )
      end

      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(underlying_state)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('underlying_trend_weak')
        expect(result.metadata[:trend_score]).to eq(8.0)
        expect(result.metadata[:threshold]).to eq(10.0)
      end
    end

    context 'when ATR collapses' do
      let(:underlying_state) do
        instance_double(
          'UnderlyingState',
          bos_state: :intact,
          trend_score: 15.0,
          atr_trend: :falling,
          atr_ratio: 0.60
        )
      end

      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(underlying_state)
      end

      it 'returns exit result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('underlying_atr_collapse')
        expect(result.metadata[:atr_ratio]).to eq(0.60)
        expect(result.metadata[:threshold]).to eq(0.65)
      end
    end

    context 'when underlying state is OK' do
      let(:underlying_state) do
        instance_double(
          'UnderlyingState',
          bos_state: :intact,
          trend_score: 15.0,
          atr_trend: :rising,
          atr_ratio: 0.8
        )
      end

      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(underlying_state)
      end

      it 'returns no_action' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when underlying monitor returns nil' do
      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(nil)
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
      it 'has priority 60' do
        expect(described_class::PRIORITY).to eq(60)
      end
    end
  end
end

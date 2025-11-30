# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::PeakDrawdownRule do
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
      current_ltp: 120.0,
      pnl: 1000.0,
      pnl_pct: 20.0,
      peak_profit_pct: 25.0,
      sl_offset_pct: 10.0
    )
  end
  let(:risk_config) do
    {
      trailing: { activation_pct: 10.0 }
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
    allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(false)
    allow(Positions::TrailingConfig).to receive(:peak_drawdown_active?).and_return(true)
    allow(Positions::TrailingConfig).to receive(:config).and_return(
      peak_drawdown_pct: 5.0,
      activation_profit_pct: 25.0,
      activation_sl_offset_pct: 10.0
    )
    allow(AlgoConfig).to receive(:fetch).and_return(feature_flags: {})
  end

  describe '#evaluate' do
    context 'when trailing activation threshold is not met' do
      before do
        position_data.pnl_pct = 5.0 # Below 10% activation threshold
        position_data.peak_profit_pct = 5.0
      end

      it 'returns skip_result when pnl_pct < activation_pct' do
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when trailing activation threshold is met' do
      before do
        position_data.pnl_pct = 20.0 # Above 10% activation threshold
        position_data.peak_profit_pct = 25.0
      end

      context 'when peak drawdown is triggered' do
      before do
        allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)
      end

      context 'when activation gating is disabled' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return(feature_flags: {})
        end

        it 'returns exit result' do
          result = rule.evaluate(context)
          expect(result.exit?).to be true
          expect(result.reason).to include('peak_drawdown_exit')
          expect(result.metadata[:peak_profit_pct]).to eq(25.0)
          expect(result.metadata[:current_profit_pct]).to eq(20.0)
          expect(result.metadata[:drawdown]).to eq(5.0)
        end
      end

      context 'when activation gating is enabled and conditions met' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return(
            feature_flags: { enable_peak_drawdown_activation: true }
          )
          allow(Positions::TrailingConfig).to receive(:peak_drawdown_active?).and_return(true)
        end

        it 'returns exit result' do
          result = rule.evaluate(context)
          expect(result.exit?).to be true
        end
      end

      context 'when activation gating is enabled but conditions not met' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return(
            feature_flags: { enable_peak_drawdown_activation: true }
          )
          allow(Positions::TrailingConfig).to receive(:peak_drawdown_active?).and_return(false)
        end

        it 'returns no_action' do
          result = rule.evaluate(context)
          expect(result.no_action?).to be true
        end
      end
    end

    context 'when peak drawdown is not triggered' do
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

    context 'when peak profit data is missing' do
      it 'returns skip_result when peak_profit_pct is nil' do
        position_data.peak_profit_pct = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when current_profit_pct is nil' do
        position_data.pnl_pct = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'with different activation thresholds' do
      it 'works with 6% activation threshold' do
        risk_config[:trailing][:activation_pct] = 6.0
        position_data.pnl_pct = 6.0
        position_data.peak_profit_pct = 10.0
        allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)

        result = rule.evaluate(context)
        expect(result.skip?).to be false
      end

      it 'skips with 6% threshold when pnl_pct is 5.99%' do
        risk_config[:trailing][:activation_pct] = 6.0
        position_data.pnl_pct = 5.99

        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 45' do
        expect(described_class::PRIORITY).to eq(45)
      end
    end
  end
end

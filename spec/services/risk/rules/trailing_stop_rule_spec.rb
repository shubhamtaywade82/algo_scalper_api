# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TrailingStopRule do
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
      current_ltp: 110.0,
      pnl: 1000.0,
      pnl_pct: 10.0,
      high_water_mark: 1200.0
    )
  end
  let(:risk_config) do
    {
      exit_drop_pct: 10.0,
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

  describe '#evaluate' do
    context 'when trailing activation threshold is not met' do
      before do
        position_data.pnl_pct = 5.0 # Below 10% activation threshold
      end

      it 'returns skip_result when pnl_pct < activation_pct' do
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when trailing activation threshold is met' do
      before do
        position_data.pnl_pct = 10.0 # Exactly at 10% activation threshold
      end

      context 'when trailing stop is triggered' do
        it 'returns exit result when HWM drop exceeds threshold' do
          # HWM: 1200, PnL: 1000, Drop: (1200-1000)/1200 = 16.67% >= 10%
          result = rule.evaluate(context)
          expect(result.exit?).to be true
          expect(result.reason).to include('TRAILING STOP')
          expect(result.metadata[:pnl]).to eq(1000.0)
          expect(result.metadata[:hwm]).to eq(1200.0)
          expect(result.metadata[:drop_pct]).to be >= 0.10
        end

        it 'triggers exit when drop exactly equals threshold' do
          position_data.pnl = 1080.0 # Drop: (1200-1080)/1200 = 10%
          result = rule.evaluate(context)
          expect(result.exit?).to be true
        end
      end
    end

    context 'when trailing stop is not triggered' do
      it 'returns no_action when drop is below threshold' do
        position_data.pnl = 1150.0 # Drop: (1200-1150)/1200 = 4.17% < 10%
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

    context 'when data is missing' do
      it 'returns skip_result when pnl is nil' do
        position_data.pnl = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when hwm is nil' do
        position_data.high_water_mark = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when hwm is zero' do
        position_data.high_water_mark = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when threshold is zero' do
      it 'returns skip_result when exit_drop_pct is 0' do
        risk_config[:exit_drop_pct] = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'with different activation thresholds' do
      it 'works with 6% activation threshold' do
        risk_config[:trailing][:activation_pct] = 6.0
        position_data.pnl_pct = 6.0
        position_data.pnl = 600.0
        position_data.high_water_mark = 800.0

        result = rule.evaluate(context)
        # Should evaluate (not skip) since 6% >= 6%
        expect(result.skip?).to be false
      end

      it 'skips with 6% threshold when pnl_pct is 5.99%' do
        risk_config[:trailing][:activation_pct] = 6.0
        position_data.pnl_pct = 5.99

        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'works with 13.32% activation threshold' do
        risk_config[:trailing][:activation_pct] = 13.32
        position_data.pnl_pct = 13.32
        position_data.pnl = 1332.0
        position_data.high_water_mark = 1500.0

        result = rule.evaluate(context)
        expect(result.skip?).to be false
      end
    end

    describe 'priority' do
      it 'has priority 50' do
        expect(described_class::PRIORITY).to eq(50)
      end
    end
  end

  describe 'spot-anchored trailing (3-layer logic)' do
    let(:tracker_dbl)    { instance_double('PositionTracker', entry_price: 100.0) }
    let(:instrument_dbl) { instance_double('Instrument') }
    let(:series_dbl)     { instance_double('CandleSeries', candles: []) }
    let(:structure_dbl)  { instance_double('Smc::Detectors::Structure') }
    let(:context_dbl) do
      instance_double(
        Risk::Rules::RuleContext,
        active?: true,
        tracker: tracker_dbl,
        tracker_snapshot: { pnl_pct: 0.30, ltp: 90.0, hwm_pnl: 3000.0, pnl: 1000.0 }
      )
    end
    let(:rule_dbl) { described_class.new(config: {}) }

    before do
      allow(tracker_dbl).to receive(:instrument).and_return(instrument_dbl)
      allow(tracker_dbl).to receive(:watchable).and_return(nil)
      allow(tracker_dbl).to receive(:side).and_return('long_pe')
      allow(instrument_dbl).to receive(:candle_series).and_return(series_dbl)
      allow(Smc::Detectors::Structure).to receive(:new).and_return(structure_dbl)
      allow(structure_dbl).to receive(:choch?).and_return(false)
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          exits: {
            trailing: {
              spot_anchored: {
                enabled: true,
                min_adx_to_hold: 15,
                hard_floor_pct: 0.50
              }
            }
          }
        }
      })
    end

    context 'Layer 1: spot trend alive — premium above hard floor' do
      before do
        allow(instrument_dbl).to receive(:supertrend_signal).and_return(:short_entry) # PE expects short
        allow(instrument_dbl).to receive(:adx).and_return(22.0)
      end

      it 'does NOT exit (holds while spot trend intact regardless of HWM drop)' do
        result = rule_dbl.evaluate(context_dbl)
        expect(result.exit?).to be false
      end
    end

    context 'Layer 2: spot trend alive — premium drops below hard floor (50% of entry)' do
      before do
        allow(instrument_dbl).to receive(:supertrend_signal).and_return(:short_entry)
        allow(instrument_dbl).to receive(:adx).and_return(22.0)
        allow(context_dbl).to receive(:tracker_snapshot).and_return(
          { pnl_pct: 0.30, ltp: 45.0, hwm_pnl: 3000.0, pnl: 1000.0 }
        )
      end

      it 'exits with TRAILING_HARD_FLOOR (premium below 50% of entry despite trend alive)' do
        result = rule_dbl.evaluate(context_dbl)
        expect(result.exit?).to be true
        expect(result.reason).to include('TRAILING_HARD_FLOOR')
      end
    end

    context 'Layer 3: spot trend broken — delegates to UEC trailing logic' do
      before do
        allow(instrument_dbl).to receive(:supertrend_signal).and_return(:long_entry) # Wrong for long_pe
        allow(instrument_dbl).to receive(:adx).and_return(10.0)
        allow(Live::UnifiedExitChecker).to receive(:send).and_return({ action: :hold, multiplier: 1.0, reason: nil })
      end

      it 'reaches UEC evaluation (spot-trend check does not short-circuit)' do
        expect(Live::UnifiedExitChecker).to receive(:send)
          .with(:evaluate_underlying_context, anything, anything)
          .and_return({ action: :hold, multiplier: 1.0, reason: nil })
        rule_dbl.evaluate(context_dbl)
      end
    end
  end
end

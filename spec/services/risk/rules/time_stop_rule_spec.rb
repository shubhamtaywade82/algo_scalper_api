# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Risk::Rules::TimeStopRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      created_at: 20.minutes.ago,
      meta: { 'index_key' => 'NIFTY', 'entry_path' => '1m_scalp' },
      instrument: nil,
      watchable: nil
    )
  end

  let(:position) do
    instance_double('Positions::ActiveCache::PositionData', pnl_pct: pnl_pct_value)
  end

  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      tracker: tracker,
      position: position,
      active?: true,
      pnl_pct: pnl_pct_value,
      tracker_snapshot: { pnl_pct: pnl_pct_value, ltp: 100.0 }
    )
  end

  let(:rule) { described_class.new(config: {}) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        time_stop: {
          scalp: { max_minutes: 15, max_candles: 15 },
          trend: { 'NIFTY' => 30, 'BANKNIFTY' => 25, 'SENSEX' => 25 }
        },
        exits: { trailing: { spot_anchored: { min_adx_to_hold: 15 } } }
      }
    })
  end

  describe 'profitable position bypass' do
    context 'when pnl_pct is 0.0 (breakeven)' do
      let(:pnl_pct_value) { 0.0 }

      it 'does NOT time-stop a breakeven position (>= 0.0 is immune)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when pnl_pct is 0.02 (+2% profit, was NOT bypassed before)' do
      let(:pnl_pct_value) { 0.02 }

      it 'bypasses time stop for any profitable position' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when pnl_pct is -0.20 (-20%, 20 minutes elapsed, scalp type)' do
      let(:pnl_pct_value) { -0.20 }

      it 'fires TIME_STOP (losing scalp past 15 min)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TIME_STOP')
      end
    end
  end

  describe 'spot trend bypass' do
    let(:pnl_pct_value) { -0.03 }  # Losing position
    let(:instrument)    { instance_double('Instrument') }
    let(:series)        { instance_double('CandleSeries', candles: []) }
    let(:structure)     { instance_double('Smc::Detectors::Structure') }

    before do
      allow(tracker).to receive(:instrument).and_return(instrument)
      allow(instrument).to receive(:candle_series).and_return(series)
      allow(Smc::Detectors::Structure).to receive(:new).and_return(structure)
      allow(structure).to receive(:choch?).and_return(false)
    end

    context 'when spot trend is intact (supertrend ok, ADX ok, no CHOCH)' do
      before do
        allow(instrument).to receive(:supertrend_signal).and_return(:long_entry)
        allow(instrument).to receive(:adx).and_return(20.0)
        allow(tracker).to receive(:side).and_return('long_ce')
      end

      it 'skips time stop (spot trend still alive)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when spot trend is broken (supertrend flipped, ADX collapsed)' do
      before do
        allow(instrument).to receive(:supertrend_signal).and_return(:short_entry)
        allow(instrument).to receive(:adx).and_return(10.0)
        allow(tracker).to receive(:side).and_return('long_ce')
      end

      it 'allows time stop to fire (spot confirms trade is dead)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end
end

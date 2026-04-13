# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::PremiumMomentumFailureRule do
  subject(:rule) { described_class.new(config: { enabled: true }) }

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      created_at: 10.minutes.ago,
      entry_price: 200.0,
      instrument: nil,
      watchable: nil,
      meta: {
        'index_key' => index_key,
        'peak_premium' => 200.0,
        'peak_premium_at' => peak_at.iso8601
      }
    )
  end

  let(:position_data) do
    OpenStruct.new(current_ltp: 190.0) # Below peak, losing
  end

  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      tracker: tracker,
      position: position_data,
      active?: true,
      pnl_pct: -0.05, # Losing position
      tracker_snapshot: { ltp: 190.0, pnl_pct: -0.05 }
    )
  end

  let(:pmf_config) do
    {
      enabled: true,
      default_stall_minutes: 3,
      index_overrides: {
        SENSEX: { stall_minutes: 4 }
      },
      session_overrides: {
        chop_decay: { stall_minutes_add: 2 },
        close_gamma: { stall_minutes_add: 2 }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        exits: {
          premium_momentum_failure: pmf_config,
          trailing: { spot_anchored: { min_adx_to_hold: 15 } }
        },
        time_regimes: {
          open_expansion: { start: '09:15', end: '09:45' },
          trend_continuation: { start: '09:45', end: '11:30' },
          chop_decay: { start: '11:30', end: '13:45' },
          close_gamma: { start: '13:45', end: '15:15' }
        }
      }
    })
  end

  describe 'index-aware stall minutes' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 4.minutes.ago }

    context 'when NIFTY morning stall exceeds default' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      end

      it 'triggers PMF exit (4 >= 3)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PREMIUM_MOMENTUM_FAILURE')
      end
    end

    context 'when SENSEX stall under index threshold' do
      let(:index_key) { 'SENSEX' }
      let(:peak_at) { 3.5.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      end

      it 'does NOT trigger PMF (3.5 < 4)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end
  end

  describe 'session-aware stall minutes' do
    let(:index_key) { 'NIFTY' }

    context 'when NIFTY chop_decay stall under sum' do
      let(:peak_at) { 4.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
      end

      it 'does NOT trigger PMF (4 < 5)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when SENSEX chop_decay meets stall sum' do
      let(:index_key) { 'SENSEX' }
      let(:peak_at) { 6.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
      end

      it 'triggers PMF exit (6 >= 6)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when NIFTY close_gamma meets stall sum' do
      let(:peak_at) { 5.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 14:00:00 +05:30'))
      end

      it 'triggers PMF exit (5 >= 5)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end

  describe 'winning position is skipped' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 5.minutes.ago }

    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      allow(context).to receive(:pnl_pct).and_return(0.05) # Winning
    end

    it 'returns no_action (winners handled by trailing)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end

  describe 'minimum loss floor gate (-5% minimum)' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at)   { 5.minutes.ago }

    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-04-13 10:00:00 +05:30'))
    end

    context 'when pnl_pct is -0.02 (only -2% loss — too shallow)' do
      before { allow(context).to receive(:pnl_pct).and_return(-0.02) }

      it 'does NOT fire PMF (loss below -5% floor)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when pnl_pct is -0.06 (-6% loss, stall >= threshold)' do
      before do
        allow(context).to receive_messages(pnl_pct: -0.06, tracker_snapshot: { ltp: 190.0, pnl_pct: -0.06 })
      end

      it 'fires PMF (loss meets -5% floor + stall time met)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end

  describe 'spot trend confirmation gate' do
    let(:index_key)  { 'NIFTY' }
    let(:peak_at)    { 5.minutes.ago }
    let(:instrument) { instance_double(Instrument) }
    let(:series)     { instance_double(CandleSeries, candles: []) }
    let(:structure)  { instance_double(Smc::Detectors::Structure) }

    before do
      # Stub Time before any let that uses 5.minutes.ago (tracker meta peak_premium_at).
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-04-13 10:00:00 +05:30'))
      allow(context).to receive_messages(pnl_pct: -0.08, tracker_snapshot: { ltp: 170.0, pnl_pct: -0.08 })
      allow(tracker).to receive_messages(instrument: instrument, watchable: nil, side: 'long_ce')
      allow(instrument).to receive(:candle_series).and_return(series)
      allow(Smc::Detectors::Structure).to receive(:new).and_return(structure)
      allow(structure).to receive(:choch?).and_return(false)
    end

    context 'when underlying spot trend is still intact' do
      before do
        allow(instrument).to receive_messages(supertrend_signal: :long_entry, adx: 20.0)
      end

      it 'does NOT fire PMF (spot not confirming failure)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when underlying spot trend has broken' do
      before do
        allow(instrument).to receive_messages(supertrend_signal: :short_entry, adx: 10.0)
      end

      it 'fires PMF (spot confirms the momentum failure)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PREMIUM_MOMENTUM_FAILURE')
      end
    end
  end
end

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
      pnl_pct: -0.05 # Losing position
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
        exits: { premium_momentum_failure: pmf_config },
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

    context 'NIFTY in morning (default 3 min) — stalled 4 min' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      end

      it 'triggers PMF exit (4 >= 3)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PREMIUM_MOMENTUM_FAILURE')
      end
    end

    context 'SENSEX in morning (base 4 min) — stalled 3.5 min' do
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

    context 'NIFTY in chop_decay (3 + 2 = 5 min) — stalled 4 min' do
      let(:peak_at) { 4.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
      end

      it 'does NOT trigger PMF (4 < 5)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'SENSEX in chop_decay (4 + 2 = 6 min) — stalled 6 min' do
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

    context 'NIFTY in close_gamma (3 + 2 = 5 min) — stalled 5 min' do
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

  describe 'fallback when config absent' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 3.minutes.ago }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
    end

    it 'falls back to DEFAULT_STALL_MINUTES (3)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be true
    end
  end

  describe 'winning position is skipped' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 5.minutes.ago }

    before do
      allow(context).to receive(:pnl_pct).and_return(0.05) # Winning
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
    end

    it 'returns no_action (winners handled by trailing)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end
end

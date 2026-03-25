# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::TrailingEngine do
  let(:instrument) { create(:instrument, symbol_name: symbol) }
  let(:tracker) do
    create(:position_tracker,
           instrument: instrument,
           entry_price: 100.0,
           quantity: 50,
           symbol: symbol,
           segment: segment)
  end
  let(:engine) { described_class.new(tracker: tracker, ltp: ltp) }

  # Stub AlgoConfig to return our calibrated values (same as algo.yml defaults)
  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        institutional_trailing: {
          enabled: true,
          session_aware: true,
          expiry_day_tightening: 0.60,
          nifty: {
            early_trigger: 0.05,
            early_sl_offset: -0.12,
            breakeven_trigger: 0.157,
            activation_trigger: 0.20,
            trailing_distance: 0.386
          },
          sensex: {
            early_trigger: 0.06,
            early_sl_offset: -0.10,
            breakeven_trigger: 0.12,
            activation_trigger: 0.18,
            trailing_distance: 0.413
          },
          banknifty: {
            early_trigger: 0.06,
            early_sl_offset: -0.15,
            breakeven_trigger: 0.18,
            activation_trigger: 0.25,
            trailing_distance: 0.35
          }
        }
      }
    })

    # Default: run tests in morning session (no tightening)
    allow(Time).to receive(:current).and_return(
      Time.zone.parse('2026-03-02 10:00:00') # Monday morning
    )
  end

  # ── NIFTY ──────────────────────────────────────────────────────────────────

  context 'with NIFTY instrument' do
    let(:symbol) { 'NIFTY24MAR22000CE' }
    let(:segment) { 'NSE_FNO' }

    describe 'Phase 1: Survival' do
      let(:ltp) { 105.0 } # +5% profit

      it 'returns survival SL at -12% from entry' do
        expect(engine.call).to eq(88.0) # 100 * (1 + (-0.12))
      end
    end

    describe 'Phase 2: Breakeven' do
      let(:ltp) { 116.0 } # +16% profit (> breakeven_trigger 15.7%)

      it 'returns breakeven SL' do
        expect(engine.call).to eq(100.0)
      end
    end

    describe 'Phase 2: below breakeven trigger' do
      let(:ltp) { 110.0 } # +10% profit (above early_trigger, below breakeven_trigger 15.7%)

      it 'returns survival SL (still in Phase 1)' do
        expect(engine.call).to eq(88.0)
      end
    end

    describe 'Phase 3: High Watermark Trailing' do
      context 'at activation (morning session — no tightening)' do
        let(:ltp) { 120.0 } # +20% profit

        it 'returns HWM SL with 38.6% distance' do
          # 120 * (1 - 0.386) = 120 * 0.614 = 73.68
          expect(engine.call).to be_within(0.01).of(73.68)
        end
      end

      context 'after making a new high' do
        let(:ltp) { 150.0 } # +50% profit

        it 'updates highest_price and returns SL from new HWM' do
          # 150 * (1 - 0.386) = 150 * 0.614 = 92.1
          expect(engine.call).to be_within(0.01).of(92.1)
          expect(tracker.highest_price.to_f).to eq(150.0)
        end
      end

      context 'after a pullback from high' do
        before do
          described_class.new(tracker: tracker, ltp: 150.0).call
        end

        let(:ltp) { 140.0 }

        it 'maintains SL from the peak' do
          # 150 * 0.614 = 92.1 (peak at 150 still)
          expect(engine.call).to be_within(0.01).of(92.1)
          expect(tracker.highest_price.to_f).to eq(150.0)
        end
      end
    end
  end

  # ── SENSEX ─────────────────────────────────────────────────────────────────

  context 'with SENSEX instrument' do
    let(:symbol) { 'SENSEX24MAR72000CE' }
    let(:segment) { 'BSE_FNO' }

    describe 'Phase 1: Survival' do
      let(:ltp) { 106.0 } # +6% profit

      it 'returns survival SL at -10% from entry' do
        expect(engine.call).to eq(90.0) # 100 * (1 + (-0.10))
      end
    end

    describe 'Phase 2: Breakeven' do
      let(:ltp) { 112.0 } # +12% profit (= breakeven_trigger 12%)

      it 'returns breakeven SL' do
        expect(engine.call).to eq(100.0)
      end
    end

    describe 'Phase 3: High Watermark Trailing' do
      let(:ltp) { 120.0 } # +20% profit (> activation 18%)

      it 'returns HWM SL with 41.3% distance' do
        # 120 * (1 - 0.413) = 120 * 0.587 = 70.44
        expect(engine.call).to be_within(0.01).of(70.44)
      end
    end
  end

  # ── BANKNIFTY ──────────────────────────────────────────────────────────────

  context 'with BANKNIFTY instrument' do
    let(:symbol) { 'BANKNIFTY24MAR50000CE' }
    let(:segment) { 'NSE_FNO' }

    describe 'Phase 1: Survival' do
      let(:ltp) { 106.0 } # +6% profit (= early_trigger)

      it 'returns survival SL at -15% from entry' do
        expect(engine.call).to eq(85.0) # 100 * (1 + (-0.15))
      end
    end

    describe 'Phase 2: Breakeven' do
      let(:ltp) { 118.0 } # +18% profit (= breakeven_trigger)

      it 'returns breakeven SL' do
        expect(engine.call).to eq(100.0)
      end
    end

    describe 'Phase 3: HWM Trailing' do
      let(:ltp) { 126.0 } # +26% profit (> activation 25%)

      it 'returns HWM SL with 35% distance' do
        # 126 * (1 - 0.35) = 126 * 0.65 = 81.9
        expect(engine.call).to be_within(0.01).of(81.9)
      end
    end

    describe 'no action below early trigger' do
      let(:ltp) { 104.0 } # +4% (below early_trigger 6%)

      it 'returns nil' do
        expect(engine.call).to be_nil
      end
    end
  end

  # ── SESSION-AWARE TRAILING ─────────────────────────────────────────────────

  context 'session-aware tightening' do
    let(:symbol) { 'NIFTY24MAR22000CE' }
    let(:segment) { 'NSE_FNO' }
    let(:ltp) { 125.0 } # +25% profit — Phase 3 active

    context 'in morning session (09:15-11:00)' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-02 10:30:00') # Monday 10:30 = morning
        )
      end

      it 'applies full trailing distance (1.0x)' do
        # 125 * (1 - 0.386 * 1.0) = 125 * 0.614 = 76.75
        expect(engine.call).to be_within(0.01).of(76.75)
      end
    end

    context 'in midday session (11:01-13:00)' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-02 12:00:00') # Monday 12:00 = midday
        )
      end

      it 'applies 0.90x trailing distance' do
        # effective distance = 0.386 * 0.90 = 0.3474
        # 125 * (1 - 0.3474) = 125 * 0.6526 = 81.575
        expect(engine.call).to be_within(0.01).of(81.575)
      end
    end

    context 'in afternoon session (13:01+)' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-02 14:30:00') # Monday 14:30 = afternoon
        )
      end

      it 'applies 0.75x trailing distance (tighter — crash risk)' do
        # effective distance = 0.386 * 0.75 = 0.2895
        # 125 * (1 - 0.2895) = 125 * 0.7105 = 88.8125
        expect(engine.call).to be_within(0.01).of(88.8125)
      end
    end
  end

  # ── EXPIRY-DAY TIGHTENING ──────────────────────────────────────────────────

  context 'expiry-day tightening (Thursday)' do
    let(:symbol) { 'NIFTY24MAR22000CE' }
    let(:segment) { 'NSE_FNO' }
    let(:ltp) { 125.0 } # +25% profit — Phase 3

    context 'on Thursday morning' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-05 10:00:00') # Thursday 10:00 = morning
        )
      end

      it 'applies expiry tightening (0.60x) combined with session factor (1.0x)' do
        # effective distance = 0.386 * 1.0 (morning) * 0.60 (expiry) = 0.2316
        # 125 * (1 - 0.2316) = 125 * 0.7684 = 96.05
        expect(engine.call).to be_within(0.01).of(96.05)
      end
    end

    context 'on Thursday afternoon' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-05 14:30:00') # Thursday 14:30 = afternoon
        )
      end

      it 'applies double tightening (0.75x session × 0.60x expiry)' do
        # effective distance = 0.386 * 0.75 * 0.60 = 0.1737
        # 125 * (1 - 0.1737) = 125 * 0.8263 = 103.2875
        expect(engine.call).to be_within(0.01).of(103.2875)
      end
    end

    context 'on non-expiry day (Monday)' do
      before do
        allow(Time).to receive(:current).and_return(
          Time.zone.parse('2026-03-02 10:00:00') # Monday morning
        )
      end

      it 'applies normal trailing distance' do
        # 125 * (1 - 0.386) = 76.75
        expect(engine.call).to be_within(0.01).of(76.75)
      end
    end
  end

  # ── CONFIG FALLBACK ────────────────────────────────────────────────────────

  context 'when AlgoConfig is unavailable' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'config unavailable')
    end

    let(:symbol) { 'NIFTY24MAR22000CE' }
    let(:segment) { 'NSE_FNO' }
    let(:ltp) { 120.0 } # +20% profit

    it 'falls back to DEFAULTS and still returns a trailing stop' do
      # Uses DEFAULTS[:nifty][:trailing_distance] = 0.386
      # session/expiry features disabled (errors caught)
      # 120 * (1 - 0.386) = 73.68
      expect(engine.call).to be_within(0.01).of(73.68)
    end
  end

  context 'when tracker meta has strategy_profile trend_controlled' do
    let(:symbol) { 'NIFTY24MAR22000CE' }
    let(:segment) { 'NSE_FNO' }
    let(:ltp) { 120.0 }

    before do
      tracker.update!(meta: tracker.meta.merge('strategy_profile' => 'trend_controlled'))
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          institutional_trailing: {
            session_aware: false,
            expiry_day_tightening: 0.60,
            nifty: {
              early_trigger: 0.05,
              early_sl_offset: -0.12,
              breakeven_trigger: 0.157,
              activation_trigger: 0.20,
              trailing_distance: 0.386
            },
            sensex: Trading::TrailingEngine::DEFAULTS[:sensex],
            banknifty: Trading::TrailingEngine::DEFAULTS[:banknifty],
            profiles: {
              trend_controlled: { trailing_distance: 0.06 }
            }
          }
        }
      })
    end

    it 'merges profile trailing_distance into symbol config' do
      expect(engine.call).to be_within(0.01).of(112.8)
    end
  end
end

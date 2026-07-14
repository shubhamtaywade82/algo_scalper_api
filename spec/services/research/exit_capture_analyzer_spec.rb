# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::ExitCaptureAnalyzer do
  # Synthetic 1-min premium candles. Shape A ("round trip", the 06-30/07-07b failure):
  # entry 100 -> peak 130 at minute 10 -> collapse to 20 by minute 30 -> flat to close.
  def round_trip_candles(base_time: Time.zone.parse("2026-07-10 09:30:00"))
    prices = []
    prices += (0..10).map { |i| 100.0 + (3.0 * i) } # 100 -> 130 (peak at idx 10)
    prices += (1..20).map { |i| [130.0 - (5.5 * i), 20.0].max } # collapse to 20
    prices += Array.new(30, 20.0) # flat
    to_candles(prices, base_time)
  end

  # Shape B ("slow grind", the 07-13 shape): entry 100, +3.0/min for 120 min, then flat.
  def slow_grind_candles(base_time: Time.zone.parse("2026-07-10 09:30:00"))
    prices = (0..120).map { |i| 100.0 + (3.0 * i) } + Array.new(30, 460.0)
    to_candles(prices, base_time)
  end

  def to_candles(closes, base_time)
    closes.each_with_index.map do |c, i|
      { timestamp: base_time + i.minutes, open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1000 }
    end
  end

  describe "STRATEGY_NAMES" do
    it "includes the original 8 and the 5 new strategies" do
      expect(described_class::STRATEGY_NAMES).to include(
        :fixed_30, :fixed_50, :trail_20, :und_ema9, :prem_ema5,
        :momentum_decay, :hybrid_divergence, :hold_to_close,
        :mfe_retrace_25, :mfe_retrace_35, :mfe_retrace_50,
        :gamma_state, :velocity_ratchet
      )
    end

    it "maps every registered strategy to a defined simulator method" do
      pending_methods = %i[simulate_velocity_ratchet] # Task 3
      described_class::STRATEGY_METHODS.each_value do |m|
        next if pending_methods.include?(m)

        expect(described_class).to respond_to(m), "missing #{m}"
      end
    end
  end

  describe ".simulate_mfe_retrace_35" do
    it "exits at peak - 0.35*MFE on the round-trip series" do
      candles = round_trip_candles
      exit_price, _time, reason = described_class.simulate_mfe_retrace_35(100.0, 1, candles)
      # peak high = 130.5, MFE = 30.5, stop = 130.5 - 0.35*30.5 = 119.825
      expect(exit_price).to be_within(0.01).of(119.83)
      expect(reason).to eq("mfe_retrace")
    end

    it "does not exit prematurely on the slow grind (rides to close)" do
      candles = slow_grind_candles
      exit_price, _time, reason = described_class.simulate_mfe_retrace_35(100.0, 1, candles)
      # stop never hit while grinding up; flat tail never retraces 35% of a 360.5-pt MFE
      expect(reason).to eq("market_close")
      expect(exit_price).to be_within(0.01).of(460.0)
    end
  end

  describe ".simulate_gamma_state" do
    it "exits via survival stop when the premium collapses before reaching +10%" do
      # entry 100, drifts down immediately -> survival stop at entry*0.88 = 88
      base = Time.zone.parse("2026-07-10 09:30:00")
      closes = (0..30).map { |i| 100.0 - (1.0 * i) }
      candles = closes.each_with_index.map do |c, i|
        { timestamp: base + i.minutes, open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1000 }
      end
      exit_price, _t, reason = described_class.simulate_gamma_state(100.0, 1, candles)
      expect(exit_price).to be_within(0.01).of(88.0)
      expect(reason).to eq("gamma_state_stop")
    end

    it "exits via exhaustion trail (peak*0.90) when velocity stalls after a rally" do
      candles = round_trip_candles
      exit_price, _t, reason = described_class.simulate_gamma_state(100.0, 1, candles)
      # Rally: velocity 3/close ≈ 2.4-3% < 5% threshold once above +10% profit,
      # so exhaustion trail peak*0.90 governs; peak high 130.5 -> stop 117.45
      expect(reason).to eq("gamma_state_stop")
      expect(exit_price).to be_within(1.0).of(117.45)
    end
  end
end

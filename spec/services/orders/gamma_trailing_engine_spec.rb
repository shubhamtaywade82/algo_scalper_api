# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::GammaTrailingEngine do
  let(:tracker) { instance_double('PositionTracker', symbol: symbol, entry_price: 100.0, highest_price: 100.0) }
  let(:symbol) { 'NIFTY24MAR22000CE' }
  let(:prices) { [100.0] }
  let(:engine) { described_class.new(position: tracker, prices: prices) }

  describe '#call' do
    context 'State 1: Early trade (profit < 10%)' do
      let(:prices) { [100.0, 105.0] }
      it 'returns 12% SL from entry' do
        expect(engine.call).to eq(88.0)
      end
    end

    context 'State 2: Trend confirmed' do
      # Velocity must be > 0.05
      # (120 - 110) / 110 = 0.09 > 0.05
      let(:prices) { [100.0, 110.0, 120.0] }
      it 'returns 20% trailing gap from peak (normal trail)' do
        # highest 120, normal_trail 0.80 -> 96.0
        expect(engine.call).to eq(96.0)
      end
    end

    context 'State 3: Gamma expansion' do
      # NIFTY: gamma_trigger 0.25, trail_gamma 0.65
      # Prices must show positive acceleration
      # v1 = (110-100)/100 = 0.10
      # v2 = (130-110)/110 = 0.18
      # acceleration = 0.08 > 0
      let(:prices) { [100.0, 110.0, 130.0] }
      it 'loosens trailing to 35% gap (trail_gamma)' do
        # highest 130, trail_gamma 0.65 -> 84.5
        expect(engine.call).to eq(84.5)
      end
    end

    context 'State 4: Exhaustion' do
      # NIFTY: velocity_threshold 0.05, trail_exhaust 0.90
      # v = (121-120)/120 = 0.0083 < 0.05
      let(:prices) { [100.0, 110.0, 120.0, 121.0] }
      it 'tightens trailing to 10% gap (trail_exhaust)' do
        # highest 120, trail_exhaust 0.90 -> 108.9 (wait, highest updated to 121)
        # 121 * 0.90 = 108.9
        expect(engine.call).to eq(108.9)
      end
    end
  end
end

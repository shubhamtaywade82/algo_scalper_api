# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::Liquidity do
  describe '#buy_side_taken?' do
    it 'returns true when liquidity grab up is detected' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: true, liquidity_grab_down?: false)

      detector = described_class.new(series)
      expect(detector.buy_side_taken?).to be(true)
    end

    it 'returns false when no liquidity grab up' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: false, liquidity_grab_down?: false)

      detector = described_class.new(series)
      expect(detector.buy_side_taken?).to be(false)
    end

    it 'handles nil series gracefully' do
      detector = described_class.new(nil)
      expect(detector.buy_side_taken?).to be(false)
    end
  end

  describe '#sell_side_taken?' do
    it 'returns true when liquidity grab down is detected' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: false, liquidity_grab_down?: true)

      detector = described_class.new(series)
      expect(detector.sell_side_taken?).to be(true)
    end

    it 'returns false when no liquidity grab down' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: false, liquidity_grab_down?: false)

      detector = described_class.new(series)
      expect(detector.sell_side_taken?).to be(false)
    end

    it 'handles nil series gracefully' do
      detector = described_class.new(nil)
      expect(detector.sell_side_taken?).to be(false)
    end
  end

  describe '#sweep_direction' do
    it 'returns :buy_side when buy side is taken' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: true, liquidity_grab_down?: false)

      detector = described_class.new(series)
      expect(detector.sweep_direction).to eq(:buy_side)
    end

    it 'returns :sell_side when sell side is taken' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: false, liquidity_grab_down?: true)

      detector = described_class.new(series)
      expect(detector.sweep_direction).to eq(:sell_side)
    end

    it 'returns nil when no liquidity is taken' do
      series = instance_double(CandleSeries)
      allow(series).to receive_messages(liquidity_grab_up?: false, liquidity_grab_down?: false)

      detector = described_class.new(series)
      expect(detector.sweep_direction).to be_nil
    end
  end

  describe '#to_h' do
    it 'serializes liquidity state' do
      series = instance_double(CandleSeries)
      allow(series).to receive(:recent_highs).with(5).and_return([])
      allow(series).to receive(:recent_lows).with(5).and_return([])
      allow(series).to receive_messages(liquidity_grab_up?: true, liquidity_grab_down?: false, highs: [100.0, 102.0],
                                        lows: [98.0, 99.0])

      detector = described_class.new(series)
      result = detector.to_h

      expect(result).to include(
        buy_side_taken: true,
        sell_side_taken: false,
        sweep_direction: :buy_side,
        equal_highs: false,
        equal_lows: false,
        sweep: true
      )
    end
  end
end

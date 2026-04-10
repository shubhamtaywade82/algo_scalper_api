# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Domain::TradingContext do
  describe '.normalize_strictness' do
    it 'maps known values' do
      expect(described_class.normalize_strictness(:relaxed)).to eq(:relaxed)
      expect(described_class.normalize_strictness('RELAXED')).to eq(:relaxed)
      expect(described_class.normalize_strictness(:strict)).to eq(:strict)
    end

    it 'falls back to strict for unknown values' do
      expect(described_class.normalize_strictness(:nope)).to eq(:strict)
      expect(described_class.normalize_strictness(nil)).to eq(:strict)
    end
  end

  describe '#tradable?' do
    context 'when strictness is relaxed' do
      it 'allows chop, low score, and low stability' do
        ctx = described_class.new(
          day_type: :expiry,
          session: :opening,
          regime: :chop,
          score: 10,
          stability: 0,
          strictness: :relaxed
        )
        expect(ctx.tradable?).to be true
      end
    end

    context 'when strictness is strict' do
      it 'rejects chop' do
        ctx = described_class.new(
          day_type: :normal,
          session: :midday,
          regime: :chop,
          score: 70,
          stability: 10,
          strictness: :strict
        )
        expect(ctx.tradable?).to be false
      end

      it 'rejects low score' do
        ctx = described_class.new(
          day_type: :normal,
          session: :midday,
          regime: :trend,
          score: 40,
          stability: 10,
          strictness: :strict
        )
        expect(ctx.tradable?).to be false
      end

      it 'rejects low stability' do
        ctx = described_class.new(
          day_type: :normal,
          session: :midday,
          regime: :trend,
          score: 60,
          stability: 2,
          strictness: :strict
        )
        expect(ctx.tradable?).to be false
      end

      it 'passes when thresholds met' do
        ctx = described_class.new(
          day_type: :normal,
          session: :midday,
          regime: :trend,
          score: 55,
          stability: 3,
          strictness: :strict
        )
        expect(ctx.tradable?).to be true
      end
    end
  end
end

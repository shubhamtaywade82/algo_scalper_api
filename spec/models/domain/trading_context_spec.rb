# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Domain::TradingContext do
  def context_for(**overrides)
    described_class.new(
      day_type: :normal, session: :morning, regime: :trend, score: 70, stability: 5, **overrides
    )
  end

  describe '.normalize_strictness' do
    it 'maps nil to :strict' do
      expect(described_class.normalize_strictness(nil)).to eq(:strict)
    end

    it 'downcases strings' do
      expect(described_class.normalize_strictness('RELAXED')).to eq(:relaxed)
    end

    it 'falls back to :strict for unknown values' do
      expect(described_class.normalize_strictness(:loose)).to eq(:strict)
    end
  end

  describe '#tradable?' do
    it 'is tradable in a trending regime with good score and stability' do
      expect(context_for).to be_tradable
    end

    it 'blocks chop regimes even with a high score' do
      expect(context_for(regime: :chop, score: 90)).not_to be_tradable
    end

    it 'blocks scores below the minimum' do
      expect(context_for(score: 45)).not_to be_tradable
    end

    it 'requires stability of at least 3' do
      expect(context_for(stability: 2)).not_to be_tradable
      expect(context_for(stability: 3)).to be_tradable
    end

    it 'uses a higher bar on expiry days' do
      expect(context_for(day_type: :expiry, score: 55)).not_to be_tradable
      expect(context_for(day_type: :expiry, score: 60)).to be_tradable
    end

    it 'bypasses all gates in relaxed mode' do
      expect(context_for(strictness: :relaxed, regime: :chop, score: 1, stability: 0)).to be_tradable
    end
  end

  describe '#min_score' do
    it 'is 60 on expiry days and 50 otherwise' do
      expect(context_for(day_type: :expiry).min_score).to eq(60)
      expect(context_for(day_type: :normal).min_score).to eq(50)
    end
  end
end

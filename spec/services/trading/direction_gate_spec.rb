# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DirectionGate do
  describe '.allow?' do
    context 'when regime is bearish' do
      it 'blocks CE trades' do
        expect(described_class.allow?(regime: :bearish, side: :CE)).to be false
      end

      it 'allows PE trades' do
        expect(described_class.allow?(regime: :bearish, side: :PE)).to be true
      end
    end

    context 'when regime is bullish' do
      it 'allows CE trades' do
        expect(described_class.allow?(regime: :bullish, side: :CE)).to be true
      end

      it 'blocks PE trades' do
        expect(described_class.allow?(regime: :bullish, side: :PE)).to be false
      end
    end

    context 'when regime is neutral' do
      it 'blocks CE trades' do
        expect(described_class.allow?(regime: :neutral, side: :CE)).to be false
      end

      it 'blocks PE trades' do
        expect(described_class.allow?(regime: :neutral, side: :PE)).to be false
      end
    end

    context 'with string inputs' do
      it 'handles string regime' do
        expect(described_class.allow?(regime: 'bearish', side: :CE)).to be false
        expect(described_class.allow?(regime: 'bullish', side: :CE)).to be true
      end

      it 'handles string side' do
        expect(described_class.allow?(regime: :bearish, side: 'CE')).to be false
        expect(described_class.allow?(regime: :bearish, side: 'PE')).to be true
      end

      it 'handles lowercase side' do
        expect(described_class.allow?(regime: :bearish, side: 'ce')).to be false
        expect(described_class.allow?(regime: :bearish, side: 'pe')).to be true
      end
    end

    context 'with nil inputs' do
      it 'treats nil regime as neutral (blocks all)' do
        expect(described_class.allow?(regime: nil, side: :CE)).to be false
        expect(described_class.allow?(regime: nil, side: :PE)).to be false
      end
    end

    context 'with invalid regime' do
      it 'treats unknown regime as neutral (blocks all)' do
        expect(described_class.allow?(regime: :unknown, side: :CE)).to be false
        expect(described_class.allow?(regime: :sideways, side: :PE)).to be false
      end
    end
  end

  describe '.blocked?' do
    it 'blocks CE in bearish regime' do
      expect(described_class.blocked?(regime: :bearish, side: :CE)).to be true
    end

    it 'allows PE in bearish regime' do
      expect(described_class.blocked?(regime: :bearish, side: :PE)).to be false
    end

    it 'allows CE in bullish regime' do
      expect(described_class.blocked?(regime: :bullish, side: :CE)).to be false
    end

    it 'blocks PE in bullish regime' do
      expect(described_class.blocked?(regime: :bullish, side: :PE)).to be true
    end

    it 'blocks CE in neutral regime' do
      expect(described_class.blocked?(regime: :neutral, side: :CE)).to be true
    end

    it 'blocks PE in neutral regime' do
      expect(described_class.blocked?(regime: :neutral, side: :PE)).to be true
    end
  end

  describe 'logging' do
    it 'logs when a trade is blocked' do
      allow(Rails.logger).to receive(:info)

      described_class.allow?(regime: :bearish, side: :CE)

      expect(Rails.logger).to have_received(:info).with(
        '[DirectionGate] blocked CE in bearish regime'
      )
    end

    it 'does not log when a trade is allowed' do
      allow(Rails.logger).to receive(:info)

      described_class.allow?(regime: :bearish, side: :PE)

      expect(Rails.logger).not_to have_received(:info)
    end
  end
end

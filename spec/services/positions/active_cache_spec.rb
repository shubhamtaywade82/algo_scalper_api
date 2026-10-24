# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ActiveCache do
  describe '.instance' do
    it 'initializes tick query dependency' do
      cache = described_class.instance
      expect(cache.instance_variable_get(:@tick_query)).to eq(Live::TickQuery)
    end
  end

  describe Positions::PositionData do
    describe '#sl_hit? and #tp_hit?' do
      context 'for long positions (CE or PE option buyers)' do
        let(:long_position) do
          described_class.new(
            entry_price: 100.0,
            sl_price: 70.0,
            tp_price: 160.0,
            current_ltp: 100.0,
            position_side: 'long'
          )
        end

        it 'triggers SL when LTP drops to or below sl_price' do
          long_position.current_ltp = 70.0
          expect(long_position.sl_hit?).to be true

          long_position.current_ltp = 65.0
          expect(long_position.sl_hit?).to be true

          long_position.current_ltp = 80.0
          expect(long_position.sl_hit?).to be false
        end

        it 'triggers TP when LTP rises to or above tp_price' do
          long_position.current_ltp = 160.0
          expect(long_position.tp_hit?).to be true

          long_position.current_ltp = 175.0
          expect(long_position.tp_hit?).to be true

          long_position.current_ltp = 150.0
          expect(long_position.tp_hit?).to be false
        end
      end

      context 'for short positions (option sellers/writers)' do
        let(:short_position) do
          described_class.new(
            entry_price: 100.0,
            sl_price: 130.0,
            tp_price: 40.0,
            current_ltp: 100.0,
            position_side: 'short'
          )
        end

        it 'triggers SL when LTP rises to or above sl_price' do
          short_position.current_ltp = 130.0
          expect(short_position.sl_hit?).to be true

          short_position.current_ltp = 135.0
          expect(short_position.sl_hit?).to be true

          short_position.current_ltp = 110.0
          expect(short_position.sl_hit?).to be false
        end

        it 'triggers TP when LTP drops to or below tp_price' do
          short_position.current_ltp = 40.0
          expect(short_position.tp_hit?).to be true

          short_position.current_ltp = 35.0
          expect(short_position.tp_hit?).to be true

          short_position.current_ltp = 50.0
          expect(short_position.tp_hit?).to be false
        end
      end
    end

    describe '#ce_position?' do
      it 'returns true for bullish/call/long_ce directions' do
        expect(described_class.new(position_direction: 'bullish').ce_position?).to be true
        expect(described_class.new(position_direction: 'long_ce').ce_position?).to be true
        expect(described_class.new(position_direction: 'ce').ce_position?).to be true
      end

      it 'returns false for bearish/put/long_pe directions' do
        expect(described_class.new(position_direction: 'bearish').ce_position?).to be false
        expect(described_class.new(position_direction: 'long_pe').ce_position?).to be false
        expect(described_class.new(position_direction: 'pe').ce_position?).to be false
      end

      it 'returns false for unknown or ambiguous directions' do
        expect(described_class.new(position_direction: 'unknown').ce_position?).to be false
        expect(described_class.new(position_direction: nil).ce_position?).to be false
      end
    end
  end
end

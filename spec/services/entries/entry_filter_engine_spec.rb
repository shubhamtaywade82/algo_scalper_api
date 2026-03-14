# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryFilterEngine do
  let(:symbol) { 'NIFTY' }
  let(:series) { instance_double(CandleSeries) }
  let(:candles) { [] }
  let(:engine) { described_class.new(series: series, symbol: symbol) }

  before do
    allow(series).to receive_messages(candles: candles, hlc: [])
    allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
  end

  describe '#valid_entry?' do
    let(:direction) { :bullish }

    context 'when BOS is confirmed' do
      before do
        allow(Entries::BosExtractor).to receive(:last_confirmed_bos).with(series).and_return({ direction: :bullish })
      end

      context 'when range expansion is sufficient' do
        before do
          # Mock 21 candles
          mock_candles = Array.new(21) { |_i| instance_double(Candle, high: 100, low: 90, close: 95) }
          # Current candle has range 20 (110-90)
          allow(mock_candles.last).to receive_messages(high: 110, low: 90)
          # Previous 20 candles have avg range 10
          allow(series).to receive(:candles).and_return(mock_candles)
        end

        context 'when ATR is rising' do
          before do
            atr_series = [instance_double(Atr, atr: 10), instance_double(Atr, atr: 11)]
            allow(TechnicalAnalysis::Atr).to receive(:calculate).and_return(atr_series)
          end

          it 'returns true' do
            expect(engine.valid_entry?(direction: :bullish)).to be true
          end
        end

        context 'when ATR is falling' do
          before do
            atr_series = [instance_double(Atr, atr: 11), instance_double(Atr, atr: 10)]
            allow(TechnicalAnalysis::Atr).to receive(:calculate).and_return(atr_series)
          end

          it 'returns false' do
            expect(engine.valid_entry?(direction: :bullish)).to be false
          end
        end
      end

      context 'when range expansion is insufficient' do
        before do
          mock_candles = Array.new(21) { |_i| instance_double(Candle, high: 100, low: 90, close: 95) }
          # Current candle has range 11 (avg is 10, threshold is 1.4x)
          allow(mock_candles.last).to receive_messages(high: 101, low: 90)
          allow(series).to receive(:candles).and_return(mock_candles)
        end

        it 'returns false' do
          expect(engine.valid_entry?(direction: :bullish)).to be false
        end
      end
    end

    context 'when BOS is missing' do
      it 'returns false' do
        expect(engine.valid_entry?(direction: :bullish)).to be false
      end
    end
  end
end

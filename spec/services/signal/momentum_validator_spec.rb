# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::MomentumValidator do
  let(:instrument) { instance_double(Instrument, symbol_name: 'NIFTY') }
  let(:series) { build(:candle_series, :with_candles) }

  describe '.validate' do
    context 'with valid inputs' do
      let(:candles) do
        [
          instance_double(Candle, high: 19400.0, low: 19350.0, close: 19380.0, open: 19360.0),
          instance_double(Candle, high: 19450.0, low: 19380.0, close: 19420.0, open: 19400.0),
          instance_double(Candle, high: 19500.0, low: 19420.0, close: 19480.0, open: 19460.0),
          instance_double(Candle, high: 19550.0, low: 19480.0, close: 19520.0, open: 19500.0),
          instance_double(Candle, high: 19600.0, low: 19520.0, close: 19580.0, open: 19540.0)
        ]
      end

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(candles.last).to receive(:close).and_return(19580.0)
        candles.each do |c|
          allow(c).to receive(:bullish?).and_return(true)
          allow(c).to receive(:bearish?).and_return(false)
        end
      end

      it 'returns valid result when minimum confirmations met' do
        result = described_class.validate(
          instrument: instrument,
          series: series,
          direction: :bullish,
          min_confirmations: 1
        )

        expect(result).to be_a(Signal::MomentumValidator::Result)
        expect(result.valid).to be true
        expect(result.score).to be >= 1
      end
    end

    context 'with invalid inputs' do
      it 'returns invalid result when instrument is missing' do
        result = described_class.validate(
          instrument: nil,
          series: series,
          direction: :bullish
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Missing instrument')
      end

      it 'returns invalid result when series is missing' do
        result = described_class.validate(
          instrument: instrument,
          series: nil,
          direction: :bullish
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Missing series')
      end

      it 'returns invalid result when direction is invalid' do
        result = described_class.validate(
          instrument: instrument,
          series: series,
          direction: :invalid
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid direction')
      end

      it 'returns invalid result when min_confirmations is out of range' do
        result = described_class.validate(
          instrument: instrument,
          series: series,
          direction: :bullish,
          min_confirmations: 4
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid min_confirmations')
      end
    end

    context 'with insufficient confirmations' do
      let(:candles) do
        [
          instance_double(Candle, high: 19500.0, low: 19450.0, close: 19480.0, open: 19470.0),
          instance_double(Candle, high: 19480.0, low: 19420.0, close: 19450.0, open: 19460.0),
          instance_double(Candle, high: 19450.0, low: 19380.0, close: 19400.0, open: 19410.0)
        ]
      end

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(candles.last).to receive(:close).and_return(19400.0)
        candles.each do |c|
          allow(c).to receive(:bullish?).and_return(false)
          allow(c).to receive(:bearish?).and_return(true)
        end
      end

      it 'returns invalid result when score < min_confirmations' do
        result = described_class.validate(
          instrument: instrument,
          series: series,
          direction: :bullish,
          min_confirmations: 1
        )

        expect(result.valid).to be false
        expect(result.score).to be < 1
      end
    end
  end

  describe '.check_body_expansion' do
    let(:candles) do
      [
        instance_double(Candle, close: 19400.0, open: 19380.0),
        instance_double(Candle, close: 19420.0, open: 19400.0),
        instance_double(Candle, close: 19440.0, open: 19420.0),
        instance_double(Candle, close: 19500.0, open: 19450.0) # Large body
      ]
    end

    before do
      allow(series).to receive(:candles).and_return(candles)
      allow(candles.last).to receive(:bullish?).and_return(true)
      allow(candles.last).to receive(:bearish?).and_return(false)
    end

    it 'confirms when body expansion >= 1.2x' do
      result = described_class.send(:check_body_expansion, series: series, direction: :bullish)
      expect(result[:confirms]).to be true
      expect(result[:reason]).to include('Body expansion')
    end

    it 'does not confirm when body expansion < 1.2x' do
      small_candles = [
        instance_double(Candle, close: 19400.0, open: 19380.0),
        instance_double(Candle, close: 19420.0, open: 19400.0),
        instance_double(Candle, close: 19440.0, open: 19420.0),
        instance_double(Candle, close: 19450.0, open: 19440.0) # Small body
      ]
      allow(series).to receive(:candles).and_return(small_candles)
      allow(small_candles.last).to receive(:bullish?).and_return(true)

      result = described_class.send(:check_body_expansion, series: series, direction: :bullish)
      expect(result[:confirms]).to be false
    end
  end

  describe '.check_premium_speed' do
    let(:candles) do
      [
        instance_double(Candle, close: 19400.0),
        instance_double(Candle, close: 19480.0) # 0.41% move
      ]
    end

    before do
      allow(series).to receive(:candles).and_return(candles)
    end

    it 'confirms when premium speed >= threshold' do
      result = described_class.send(:check_premium_speed, instrument: instrument, series: series, direction: :bullish)
      expect(result[:confirms]).to be true
      expect(result[:reason]).to include('Premium speed')
    end

    it 'uses index-specific thresholds' do
      banknifty_instrument = instance_double(Instrument, symbol_name: 'BANKNIFTY')
      small_move_candles = [
        instance_double(Candle, close: 19400.0),
        instance_double(Candle, close: 19430.0) # 0.15% move (below BANKNIFTY threshold)
      ]
      allow(series).to receive(:candles).and_return(small_move_candles)

      result = described_class.send(:check_premium_speed, instrument: banknifty_instrument, series: series, direction: :bullish)
      expect(result[:confirms]).to be false
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::DirectionValidator do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13'
    }
  end

  let(:instrument) { instance_double(Instrument) }
  let(:primary_series) { build(:candle_series, :with_candles) }
  let(:primary_supertrend) { { trend: :bullish, last_value: 19500.0 } }
  let(:primary_adx) { 18.5 }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      signals: {
        supertrend: { period: 7, multiplier: 3.0 },
        enhanced_validation: {
          direction: {
            min_agreement: 2,
            adx_thresholds: {
              NIFTY: 15,
              BANKNIFTY: 20,
              SENSEX: 15
            }
          }
        }
      }
    })
  end

  describe '.validate' do
    context 'with valid inputs' do
      before do
        allow(instrument).to receive(:candle_series).with(interval: '15').and_return(primary_series)
        allow(instrument).to receive(:adx).with(14, interval: '15').and_return(18.0)
        allow(Entries::VWAPUtils).to receive(:calculate_vwap).and_return(19450.0)
        allow(Entries::StructureDetector).to receive(:bos_direction).and_return(:bullish)
        allow(Entries::StructureDetector).to receive(:choch?).and_return(:bullish)
        allow(Indicators::Supertrend).to receive(:new).and_return(
          instance_double(Indicators::Supertrend, call: { trend: :bullish })
        )
      end

      it 'returns valid result when minimum factors agree' do
        # Mock candles with higher highs pattern
        candles = [
          instance_double(Candle, high: 19400.0, low: 19350.0, close: 19380.0),
          instance_double(Candle, high: 19450.0, low: 19380.0, close: 19420.0),
          instance_double(Candle, high: 19500.0, low: 19420.0, close: 19480.0),
          instance_double(Candle, high: 19550.0, low: 19480.0, close: 19520.0),
          instance_double(Candle, high: 19600.0, low: 19520.0, close: 19580.0)
        ]
        allow(primary_series).to receive(:candles).and_return(candles)
        allow(candles.last).to receive(:close).and_return(19580.0)

        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: primary_series,
          primary_supertrend: primary_supertrend,
          primary_adx: primary_adx,
          min_agreement: 2
        )

        expect(result).to be_a(Signal::DirectionValidator::Result)
        expect(result.valid).to be true
        expect(result.direction).to eq(:bullish)
        expect(result.score).to be >= 2
      end
    end

    context 'with invalid inputs' do
      it 'returns invalid result when instrument is missing' do
        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: nil,
          primary_series: primary_series,
          primary_supertrend: primary_supertrend,
          primary_adx: primary_adx
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Missing instrument')
      end

      it 'returns invalid result when primary_series is missing' do
        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: nil,
          primary_supertrend: primary_supertrend,
          primary_adx: primary_adx
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Missing primary_series')
      end

      it 'returns invalid result when primary_supertrend is invalid' do
        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: primary_series,
          primary_supertrend: 'invalid',
          primary_adx: primary_adx
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid primary_supertrend')
      end

      it 'returns invalid result when primary_adx is invalid' do
        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: primary_series,
          primary_supertrend: primary_supertrend,
          primary_adx: 'invalid'
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid primary_adx')
      end

      it 'returns invalid result when min_agreement is out of range' do
        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: primary_series,
          primary_supertrend: primary_supertrend,
          primary_adx: primary_adx,
          min_agreement: 7
        )

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid min_agreement')
      end
    end

    context 'with insufficient agreement' do
      before do
        allow(instrument).to receive(:candle_series).with(interval: '15').and_return(nil)
        allow(Entries::VWAPUtils).to receive(:calculate_vwap).and_return(19600.0) # Above price (bearish)
        allow(Entries::StructureDetector).to receive(:bos_direction).and_return(:neutral)
        allow(Entries::StructureDetector).to receive(:choch?).and_return(:neutral)
      end

      it 'returns invalid result when score < min_agreement' do
        candles = [
          instance_double(Candle, high: 19500.0, low: 19450.0, close: 19480.0),
          instance_double(Candle, high: 19480.0, low: 19420.0, close: 19450.0),
          instance_double(Candle, high: 19450.0, low: 19380.0, close: 19400.0)
        ]
        allow(primary_series).to receive(:candles).and_return(candles)
        allow(candles.last).to receive(:close).and_return(19400.0)

        result = described_class.validate(
          index_cfg: index_cfg,
          instrument: instrument,
          primary_series: primary_series,
          primary_supertrend: primary_supertrend,
          primary_adx: primary_adx,
          min_agreement: 2
        )

        expect(result.valid).to be false
        expect(result.score).to be < 2
      end
    end
  end

  describe '.check_adx_strength' do
    it 'agrees when ADX >= threshold' do
      result = described_class.send(:check_adx_strength, adx: 18.0, index_cfg: index_cfg)
      expect(result[:agrees]).to be true
      expect(result[:reason]).to include('ADX 18.0 >= 15')
    end

    it 'disagrees when ADX < threshold' do
      result = described_class.send(:check_adx_strength, adx: 12.0, index_cfg: index_cfg)
      expect(result[:agrees]).to be false
      expect(result[:reason]).to include('ADX 12.0 < 15')
    end

    it 'uses index-specific thresholds' do
      banknifty_cfg = index_cfg.merge(key: 'BANKNIFTY')
      result = described_class.send(:check_adx_strength, adx: 18.0, index_cfg: banknifty_cfg)
      expect(result[:agrees]).to be false
      expect(result[:reason]).to include('ADX 18.0 < 20')
    end
  end

  describe '.check_vwap_position' do
    let(:candles) do
      [
        instance_double(Candle, close: 19400.0),
        instance_double(Candle, close: 19450.0),
        instance_double(Candle, close: 19500.0)
      ]
    end

    before do
      allow(primary_series).to receive(:candles).and_return(candles)
      allow(candles.last).to receive(:close).and_return(19500.0)
    end

    it 'agrees when price is above VWAP for bullish' do
      allow(Entries::VWAPUtils).to receive(:calculate_vwap).and_return(19450.0)
      result = described_class.send(:check_vwap_position, series: primary_series, direction: :bullish)
      expect(result[:agrees]).to be true
    end

    it 'disagrees when price is below VWAP for bullish' do
      allow(Entries::VWAPUtils).to receive(:calculate_vwap).and_return(19600.0)
      result = described_class.send(:check_vwap_position, series: primary_series, direction: :bullish)
      expect(result[:agrees]).to be false
    end
  end

  describe '.check_candle_structure' do
    context 'with bullish direction' do
      let(:candles) do
        [
          instance_double(Candle, high: 19400.0),
          instance_double(Candle, high: 19450.0),
          instance_double(Candle, high: 19500.0),
          instance_double(Candle, high: 19550.0),
          instance_double(Candle, high: 19600.0)
        ]
      end

      before do
        allow(primary_series).to receive(:candles).and_return(candles)
      end

      it 'agrees when higher highs pattern detected' do
        result = described_class.send(:check_candle_structure, series: primary_series, direction: :bullish)
        expect(result[:agrees]).to be true
        expect(result[:reason]).to include('Higher highs pattern')
      end
    end

    context 'with bearish direction' do
      let(:candles) do
        [
          instance_double(Candle, low: 19600.0),
          instance_double(Candle, low: 19550.0),
          instance_double(Candle, low: 19500.0),
          instance_double(Candle, low: 19450.0),
          instance_double(Candle, low: 19400.0)
        ]
      end

      before do
        allow(primary_series).to receive(:candles).and_return(candles)
      end

      it 'agrees when lower lows pattern detected' do
        result = described_class.send(:check_candle_structure, series: primary_series, direction: :bearish)
        expect(result[:agrees]).to be true
        expect(result[:reason]).to include('Lower lows pattern')
      end
    end
  end
end

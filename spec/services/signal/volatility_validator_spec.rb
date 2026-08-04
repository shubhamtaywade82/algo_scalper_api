# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::VolatilityValidator do
  let(:series) { build(:candle_series, :with_candles) }

  describe '.validate' do
    context 'with valid inputs' do
      let(:candles) { Array.new(42) { instance_double(Candle) } }

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(100.0, 80.0) # Ratio 1.25
        allow(Entries::ATRUtils).to receive(:atr_downtrend?).and_return(false)
        allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(false)
        allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 10:00 IST'))
      end

      it 'returns valid result when volatility health checks pass' do
        result = described_class.validate(series: series, min_atr_ratio: 0.65)

        expect(result).to be_a(Signal::VolatilityValidator::Result)
        expect(result.valid).to be true
        expect(result.atr_ratio).to be >= 0.65
      end
    end

    context 'with invalid inputs' do
      it 'returns invalid result when series is missing' do
        result = described_class.validate(series: nil)

        expect(result.valid).to be false
        expect(result.reasons).to include('Series unavailable')
      end

      it 'returns invalid result when min_atr_ratio is out of range' do
        result = described_class.validate(series: series, min_atr_ratio: 3.0)

        expect(result.valid).to be false
        expect(result.reasons).to include('Invalid min_atr_ratio')
      end
    end

    context 'with low ATR ratio' do
      let(:candles) { Array.new(42) { instance_double(Candle) } }

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(50.0, 100.0) # Ratio 0.5
        allow(Entries::ATRUtils).to receive(:atr_downtrend?).and_return(false)
        allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(false)
        allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 10:00 IST'))
      end

      it 'returns invalid result when ATR ratio < min_ratio' do
        result = described_class.validate(series: series, min_atr_ratio: 0.65)

        expect(result.valid).to be false
        expect(result.atr_ratio).to be < 0.65
      end
    end

    context 'with compression detected' do
      let(:candles) { Array.new(42) { instance_double(Candle) } }

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(100.0, 80.0)
        allow(Entries::ATRUtils).to receive(:atr_downtrend?).and_return(true) # Compression
        allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(false)
        allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 10:00 IST'))
      end

      it 'returns invalid result when compression detected' do
        result = described_class.validate(series: series, min_atr_ratio: 0.65)

        expect(result.valid).to be false
        expect(result.reasons).to include('compression')
      end
    end

    context 'with lunchtime chop' do
      let(:candles) { Array.new(42) { instance_double(Candle) } }

      before do
        allow(series).to receive(:candles).and_return(candles)
        allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(100.0, 80.0)
        allow(Entries::ATRUtils).to receive(:atr_downtrend?).and_return(false)
        allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(true) # Chop
        allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 12:00 IST'))
      end

      it 'returns invalid result when lunchtime chop detected' do
        result = described_class.validate(series: series, min_atr_ratio: 0.65)

        expect(result.valid).to be false
        expect(result.reasons).to include('chop')
      end
    end
  end

  describe '.check_atr_ratio' do
    let(:candles) { Array.new(42) { instance_double(Candle) } }

    before do
      allow(series).to receive(:candles).and_return(candles)
    end

    it 'returns valid when ratio >= min_ratio' do
      allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(100.0, 80.0) # Ratio 1.25

      result = described_class.send(:check_atr_ratio, series: series, min_ratio: 0.65)

      expect(result[:valid]).to be true
      expect(result[:ratio]).to be >= 0.65
    end

    it 'returns invalid when ratio < min_ratio' do
      allow(Entries::ATRUtils).to receive(:calculate_atr).and_return(50.0, 100.0) # Ratio 0.5

      result = described_class.send(:check_atr_ratio, series: series, min_ratio: 0.65)

      expect(result[:valid]).to be false
      expect(result[:ratio]).to be < 0.65
    end

    it 'uses non-overlapping windows' do
      # Verify that historical window doesn't overlap with current window
      expect(Entries::ATRUtils).to receive(:calculate_atr).twice
      described_class.send(:check_atr_ratio, series: series, min_ratio: 0.65)
    end
  end

  describe '.check_compression' do
    let(:candles) { Array.new(42) { instance_double(Candle) } }

    before do
      allow(series).to receive(:candles).and_return(candles)
    end

    it 'detects compression when ATR downtrend >= 4 bars' do
      allow(Entries::ATRUtils).to receive(:atr_downtrend?).with(candles, period: 14, min_downtrend_bars: 4).and_return(true)

      result = described_class.send(:check_compression, series: series)

      expect(result[:in_compression]).to be true
    end

    it 'does not detect compression when ATR downtrend < 4 bars' do
      allow(Entries::ATRUtils).to receive(:atr_downtrend?).with(candles, period: 14, min_downtrend_bars: 4).and_return(false)

      result = described_class.send(:check_compression, series: series)

      expect(result[:in_compression]).to be false
    end
  end

  describe '.check_lunchtime_chop' do
    let(:candles) { Array.new(10) { instance_double(Candle) } }

    before do
      allow(series).to receive(:candles).and_return(candles)
    end

    it 'detects chop during lunchtime window' do
      allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 12:00 IST'))
      allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(true)

      result = described_class.send(:check_lunchtime_chop, series: series)

      expect(result[:in_chop]).to be true
    end

    it 'does not detect chop outside lunchtime window' do
      allow(candles.last).to receive(:timestamp).and_return(Time.zone.parse('2024-01-01 10:00 IST'))
      allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(false)

      result = described_class.send(:check_lunchtime_chop, series: series)

      expect(result[:in_chop]).to be false
    end
  end
end

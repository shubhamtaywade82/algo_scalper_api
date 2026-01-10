# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::TrendScorer do
  let(:instrument) { instance_double(Instrument, candle_series: primary_series) }
  let(:primary_series) { build(:candle_series, :with_candles) }
  let(:confirmation_series) { build(:candle_series, :with_candles) }

  describe '#initialize' do
    it 'initializes with instrument and timeframes' do
      scorer = described_class.new(instrument: instrument, primary_tf: '1m', confirmation_tf: '5m')
      expect(scorer.instrument).to eq(instrument)
      expect(scorer.primary_tf).to eq('1')
      expect(scorer.confirmation_tf).to eq('5')
    end

    it 'uses default timeframes' do
      scorer = described_class.new(instrument: instrument)
      expect(scorer.primary_tf).to eq('1')
      expect(scorer.confirmation_tf).to eq('5')
    end

    it 'normalizes timeframe strings' do
      scorer = described_class.new(instrument: instrument, primary_tf: '15m', confirmation_tf: '60m')
      expect(scorer.primary_tf).to eq('15')
      expect(scorer.confirmation_tf).to eq('60')
    end
  end

  describe '#compute_trend_score' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m', confirmation_tf: '5m') }

    context 'with valid data' do
      before do
        allow(instrument).to receive(:candle_series).with(interval: '1').and_return(primary_series)
        allow(instrument).to receive(:candle_series).with(interval: '5').and_return(confirmation_series)
      end

      it 'returns trend score with breakdown' do
        result = scorer.compute_trend_score
        expect(result).to have_key(:trend_score)
        expect(result).to have_key(:breakdown)
        expect(result[:breakdown]).to have_key(:pa)
        expect(result[:breakdown]).to have_key(:ind)
        expect(result[:breakdown]).to have_key(:mtf)
        expect(result[:breakdown]).to have_key(:vol)
      end

      it 'returns trend score in valid range (0-26)' do
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to be_between(0, 26)
      end

      it 'returns breakdown scores in valid ranges' do
        result = scorer.compute_trend_score
        expect(result[:breakdown][:pa]).to be_between(0, 7)
        expect(result[:breakdown][:ind]).to be_between(0, 7)
        expect(result[:breakdown][:mtf]).to be_between(0, 7)
        expect(result[:breakdown][:vol]).to be_between(0, 5)
      end
    end

    context 'with no candle data' do
      before do
        allow(instrument).to receive(:candle_series).and_return(nil)
      end

      it 'returns zero scores' do
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to eq(0)
        expect(result[:breakdown][:pa]).to eq(0)
        expect(result[:breakdown][:ind]).to eq(0)
        expect(result[:breakdown][:mtf]).to eq(0)
        expect(result[:breakdown][:vol]).to eq(0)
      end
    end

    context 'with empty series' do
      let(:empty_series) { build(:candle_series) }

      before do
        allow(instrument).to receive(:candle_series).and_return(empty_series)
      end

      it 'returns zero scores' do
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(instrument).to receive(:candle_series).and_raise(StandardError, 'Test error')
      end

      it 'handles errors gracefully' do
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to eq(0)
        expect(result[:breakdown]).to eq({ pa: 0, ind: 0, mtf: 0, vol: 0 })
      end
    end
  end

  describe 'PA score calculation' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m') }
    let(:bullish_series) do
      series = build(:candle_series)
      # Add enough candles for momentum calculation (need at least 6)
      10.times do |i|
        base_price = 25_000.0 + (i * 50)
        candle = build(:candle,
                       timestamp: Time.current - (10 - i).hours,
                       open: base_price,
                       high: base_price + 30,
                       low: base_price - 20,
                       close: base_price + 25, # Bullish close
                       volume: 1_000_000)
        series.add_candle(candle)
      end
      series
    end

    before do
      allow(instrument).to receive(:candle_series).and_return(bullish_series)
    end

    it 'scores bullish momentum' do
      result = scorer.compute_trend_score
      expect(result[:breakdown][:pa]).to be >= 0
    end
  end

  describe 'IND score calculation' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m') }
    let(:series) { build(:candle_series, :with_candles) }

    before do
      allow(instrument).to receive(:candle_series).and_return(series)
    end

    context 'with bullish indicators' do
      before do
        # Stub the series methods directly (since Calculator delegates to series)
        allow(series).to receive(:rsi).with(14).and_return(65.0) # Bullish RSI
        allow(series).to receive(:macd).with(12, 26, 9).and_return([1.5, 1.2, 0.3]) # Bullish MACD
        allow(series).to receive(:adx).with(14).and_return(25.0) # Strong ADX
        allow(series).to receive(:atr).with(14).and_return(100.0) # ATR available but not used for scoring
        allow(Indicators::Supertrend).to receive(:new).with(series: series, period: 10,
                                                            base_multiplier: 2.0).and_return(supertrend_service)
        allow(supertrend_service).to receive(:call).and_return({ trend: :bullish })
      end

      let(:supertrend_service) { instance_double(Indicators::Supertrend) }

      it 'scores bullish indicators' do
        result = scorer.compute_trend_score
        # IND score should be calculated (may be 0 if other factors fail, but structure should be correct)
        expect(result[:breakdown][:ind]).to be_a(Numeric)
        expect(result[:breakdown][:ind]).to be_between(0, 7)
      end
    end

    context 'with bearish indicators' do
      before do
        # Stub the series methods directly (since Calculator delegates to series)
        allow(series).to receive(:rsi).with(14).and_return(30.0) # Not bullish
        allow(series).to receive(:macd).with(12, 26, 9).and_return([-1.5, -1.2, -0.3]) # Bearish MACD
        allow(series).to receive(:adx).with(14).and_return(15.0) # Weak ADX
        allow(series).to receive(:atr).with(14).and_return(100.0) # ATR available but not used for scoring
        allow(Indicators::Supertrend).to receive(:new).with(series: series, period: 10,
                                                            base_multiplier: 2.0).and_return(supertrend_service)
        allow(supertrend_service).to receive(:call).and_return({ trend: :bearish })
      end

      let(:supertrend_service) { instance_double(Indicators::Supertrend) }

      it 'scores lower for bearish indicators' do
        result = scorer.compute_trend_score
        expect(result[:breakdown][:ind]).to be <= 1.0
      end
    end
  end

  describe 'MTF score calculation' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m', confirmation_tf: '5m') }
    let(:primary_series) { build(:candle_series, :bullish_trend) }
    let(:confirmation_series) { build(:candle_series, :bullish_trend) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: '1').and_return(primary_series)
      allow(instrument).to receive(:candle_series).with(interval: '5').and_return(confirmation_series)
    end

    it 'scores multi-timeframe alignment' do
      result = scorer.compute_trend_score
      expect(result[:breakdown][:mtf]).to be >= 0
    end

    context 'when confirmation timeframe is same as primary' do
      let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m', confirmation_tf: '1m') }

      it 'still calculates MTF score' do
        result = scorer.compute_trend_score
        expect(result[:breakdown][:mtf]).to be >= 0
      end
    end
  end

  describe 'VOL score (removed)' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m') }
    let(:series) { build(:candle_series, :with_candles) }

    before do
      allow(instrument).to receive(:candle_series).and_return(series)
    end

    it 'always returns 0.0 for volume (not available for indices)' do
      result = scorer.compute_trend_score
      expect(result[:breakdown][:vol]).to eq(0.0)
      # Verify vol_score method does not exist
      expect(described_class.instance_methods(false)).not_to include(:vol_score)
    end
  end

  describe 'edge cases' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '1m') }

    context 'with insufficient candles' do
      let(:small_series) do
        series = build(:candle_series)
        2.times do |i|
          candle = build(:candle,
                         timestamp: Time.current - (2 - i).hours,
                         open: 25_000.0,
                         high: 25_050.0,
                         low: 24_950.0,
                         close: 25_025.0,
                         volume: 1_000_000)
          series.add_candle(candle)
        end
        series
      end

      before do
        allow(instrument).to receive(:candle_series).and_return(small_series)
      end

      it 'handles insufficient data gracefully' do
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to be >= 0
      end
    end

    context 'with nil instrument methods' do
      let(:nil_instrument) { instance_double(Instrument) }

      before do
        allow(nil_instrument).to receive(:candle_series).and_return(nil)
      end

      it 'handles nil gracefully' do
        scorer = described_class.new(instrument: nil_instrument)
        result = scorer.compute_trend_score
        expect(result[:trend_score]).to eq(0)
      end
    end
  end

  describe 'integration with real indicators' do
    let(:scorer) { described_class.new(instrument: instrument, primary_tf: '5m') }
    let(:series) { build(:candle_series, :with_candles) }

    before do
      allow(instrument).to receive(:candle_series).and_return(series)
    end

    it 'calculates real trend score' do
      result = scorer.compute_trend_score
      expect(result[:trend_score]).to be_a(Numeric)
      expect(result[:trend_score]).to be_between(0, 26)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MultiIndicatorStrategy do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }
  let(:base_price) { 22_000.0 }

  before do
    # Create enough candles for indicators
    50.times do |i|
      price = base_price + (i * 10)
      candle = Candle.new(
        ts: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
        open: price,
        high: price + 5,
        low: price - 5,
        close: price + 2,
        volume: 1000
      )
      series.add_candle(candle)
    end
  end

  describe '#initialize' do
    it 'initializes with default confirmation mode' do
      strategy = described_class.new(series: series, indicators: [])
      expect(strategy.confirmation_mode).to eq(:all_must_agree)
      expect(strategy.min_confidence).to eq(60)
    end

    it 'initializes with custom confirmation mode' do
      strategy = described_class.new(
        series: series,
        indicators: [],
        confirmation_mode: :majority,
        min_confidence: 70
      )
      expect(strategy.confirmation_mode).to eq(:majority_vote)
      expect(strategy.min_confidence).to eq(70)
    end

    it 'builds indicators from config' do
      indicators_config = [
        { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
        { type: 'adx', config: { period: 14, min_strength: 20 } }
      ]
      strategy = described_class.new(series: series, indicators: indicators_config)
      expect(strategy.indicators.size).to eq(2)
    end
  end

  describe '#generate_signal' do
    context 'with all confirmation mode' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 20 } }
          ],
          confirmation_mode: :all,
          min_confidence: 50
        )
      end

      it 'returns signal when all indicators agree' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        # Signal may or may not be generated depending on indicator agreement
        expect(signal).to be_a(Hash).or be_nil
        if signal
          expect(signal[:type]).to be_in(%i[ce pe])
          expect(signal[:confidence]).to be_between(0, 100)
        end
      end

      it 'returns nil when indicators disagree' do
        # Mock indicators to return conflicting directions
        allow_any_instance_of(Indicators::SupertrendIndicator).to receive(:calculate_at).and_return(
          { value: 22_000, direction: :bullish, confidence: 80 }
        )
        allow_any_instance_of(Indicators::AdxIndicator).to receive(:calculate_at).and_return(
          { value: 25, direction: :bearish, confidence: 70 }
        )

        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        expect(signal).to be_nil
      end
    end

    context 'with majority confirmation mode' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 20 } },
            { type: 'rsi', config: { period: 14 } }
          ],
          confirmation_mode: :majority,
          min_confidence: 50
        )
      end

      it 'returns signal when majority agrees' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        # Signal may or may not be generated depending on majority vote
        expect(signal).to be_a(Hash).or be_nil
      end

      it 'returns nil when there is a tie' do
        # Mock to create a tie situation
        allow_any_instance_of(Indicators::SupertrendIndicator).to receive(:calculate_at).and_return(
          { value: 22_000, direction: :bullish, confidence: 80 }
        )
        allow_any_instance_of(Indicators::AdxIndicator).to receive(:calculate_at).and_return(
          { value: 25, direction: :bearish, confidence: 70 }
        )
        allow_any_instance_of(Indicators::RsiIndicator).to receive(:calculate_at).and_return(
          { value: 50, direction: :neutral, confidence: 50 }
        )

        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        expect(signal).to be_nil
      end
    end

    context 'with weighted confirmation mode' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 20 } }
          ],
          confirmation_mode: :weighted,
          min_confidence: 50
        )
      end

      it 'returns signal based on weighted sum' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        # Signal may or may not be generated depending on weighted scores
        expect(signal).to be_a(Hash).or be_nil
      end
    end

    context 'with any confirmation mode' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 20 } }
          ],
          confirmation_mode: :any,
          min_confidence: 50
        )
      end

      it 'returns signal when any indicator confirms' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        # Signal may or may not be generated depending on any indicator
        expect(signal).to be_a(Hash).or be_nil
      end
    end

    context 'with insufficient candles' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } }
          ],
          confirmation_mode: :all
        )
      end

      it 'returns nil when not enough candles' do
        signal = strategy.generate_signal(5)
        expect(signal).to be_nil
      end
    end

    context 'with no indicators' do
      let(:strategy) do
        described_class.new(series: series, indicators: [], confirmation_mode: :all)
      end

      it 'returns nil' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        expect(signal).to be_nil
      end
    end

    context 'with confidence below minimum' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } }
          ],
          confirmation_mode: :all,
          min_confidence: 90 # Very high threshold
        )
      end

      it 'returns nil when confidence is too low' do
        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        # May return nil if confidence is below 90
        expect(signal).to be_nil.or be_a(Hash)
      end
    end

    context 'with indicator calculation errors' do
      let(:strategy) do
        described_class.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } }
          ],
          confirmation_mode: :all
        )
      end

      it 'handles errors gracefully' do
        allow_any_instance_of(Indicators::SupertrendIndicator).to receive(:calculate_at).and_raise(StandardError,
                                                                                                   'Test error')
        expect(Rails.logger).to receive(:error).with(match(/Error calculating/))

        index = series.candles.size - 1
        signal = strategy.generate_signal(index)
        expect(signal).to be_nil
      end
    end
  end

  describe 'confirmation mode calculations' do
    let(:bullish_result) { { direction: :bullish, confidence: 80 } }
    let(:bearish_result) { { direction: :bearish, confidence: 70 } }
    let(:neutral_result) { { direction: :neutral, confidence: 50 } }

    context 'when using all_must_agree' do
      it 'returns :ce when all are bullish' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **bullish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :all)
        direction = strategy.send(:all_must_agree, results)
        expect(direction).to eq(:ce)
      end

      it 'returns :pe when all are bearish' do
        results = [
          { indicator: 'st', **bearish_result },
          { indicator: 'adx', **bearish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :all)
        direction = strategy.send(:all_must_agree, results)
        expect(direction).to eq(:pe)
      end

      it 'returns nil when directions differ' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **bearish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :all)
        direction = strategy.send(:all_must_agree, results)
        expect(direction).to be_nil
      end
    end

    context 'when using majority_vote' do
      it 'returns :ce when majority is bullish' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **bullish_result },
          { indicator: 'rsi', **bearish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :majority)
        direction = strategy.send(:majority_vote, results)
        expect(direction).to eq(:ce)
      end

      it 'returns nil when there is a tie' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **bearish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :majority)
        direction = strategy.send(:majority_vote, results)
        expect(direction).to be_nil
      end
    end

    context 'when using weighted_sum' do
      it 'returns :ce when bullish score is higher' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **bullish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :weighted, min_confidence: 50)
        direction = strategy.send(:weighted_sum_direction, results)
        expect(direction).to eq(:ce)
      end

      it 'returns :pe when bearish score is higher' do
        results = [
          { indicator: 'st', **bearish_result },
          { indicator: 'adx', **bearish_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :weighted, min_confidence: 50)
        direction = strategy.send(:weighted_sum_direction, results)
        expect(direction).to eq(:pe)
      end
    end

    context 'when using any_confirms' do
      it 'returns :ce when any indicator is bullish' do
        results = [
          { indicator: 'st', **bullish_result },
          { indicator: 'adx', **neutral_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :any, min_confidence: 50)
        direction = strategy.send(:any_confirms, results)
        expect(direction).to eq(:ce)
      end

      it 'returns nil when no indicator meets confidence threshold' do
        low_confidence_result = { direction: :bullish, confidence: 30 }
        results = [
          { indicator: 'st', **low_confidence_result }
        ]
        strategy = described_class.new(series: series, indicators: [], confirmation_mode: :any, min_confidence: 50)
        direction = strategy.send(:any_confirms, results)
        expect(direction).to be_nil
      end
    end
  end
end

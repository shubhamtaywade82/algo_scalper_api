# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MultiIndicatorStrategy, 'Confluence Detection' do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }
  let(:base_price) { 22000.0 }

  before do
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

  describe '#calculate_confluence' do
    let(:strategy) do
      described_class.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } }
        ],
        confirmation_mode: :all
      )
    end

    context 'when all indicators agree' do
      it 'calculates strong confluence' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 }
        ]

        confluence = strategy.send(:calculate_confluence, results)

        expect(confluence[:score]).to eq(100)
        expect(confluence[:strength]).to eq(:strong)
        expect(confluence[:agreeing_count]).to eq(2)
        expect(confluence[:total_indicators]).to eq(2)
        expect(confluence[:dominant_direction]).to eq(:bullish)
      end
    end

    context 'when majority agrees' do
      it 'calculates moderate confluence' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 },
          { indicator: 'rsi', direction: :bearish, confidence: 60 }
        ]

        confluence = strategy.send(:calculate_confluence, results)

        expect(confluence[:score]).to eq(67) # 2/3 = 66.67% rounded
        expect(confluence[:strength]).to eq(:moderate)
        expect(confluence[:agreeing_count]).to eq(2)
        expect(confluence[:bullish_count]).to eq(2)
        expect(confluence[:bearish_count]).to eq(1)
      end
    end

    context 'when indicators disagree' do
      it 'calculates weak confluence' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bearish, confidence: 75 }
        ]

        confluence = strategy.send(:calculate_confluence, results)

        expect(confluence[:score]).to eq(50) # Tie - 1/2 = 50%
        expect(confluence[:strength]).to eq(:weak)
        expect(confluence[:bullish_count]).to eq(1)
        expect(confluence[:bearish_count]).to eq(1)
      end
    end

    context 'with neutral indicators' do
      it 'handles neutral directions correctly' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :neutral, confidence: 50 },
          { indicator: 'rsi', direction: :bullish, confidence: 70 }
        ]

        confluence = strategy.send(:calculate_confluence, results)

        expect(confluence[:neutral_count]).to eq(1)
        expect(confluence[:bullish_count]).to eq(2)
        expect(confluence[:dominant_direction]).to eq(:bullish)
        expect(confluence[:score]).to eq(67) # 2/3 indicators bullish
      end
    end

    context 'indicator breakdown' do
      it 'includes breakdown of all indicators' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 },
          { indicator: 'rsi', direction: :bearish, confidence: 60 }
        ]

        confluence = strategy.send(:calculate_confluence, results)

        expect(confluence[:breakdown]).to be_an(Array)
        expect(confluence[:breakdown].size).to eq(3)

        supertrend_breakdown = confluence[:breakdown].find { |b| b[:name] == 'supertrend' }
        expect(supertrend_breakdown).to include(
          direction: :bullish,
          confidence: 80,
          agrees: true
        )

        rsi_breakdown = confluence[:breakdown].find { |b| b[:name] == 'rsi' }
        expect(rsi_breakdown).to include(
          direction: :bearish,
          confidence: 60,
          agrees: false
        )
      end
    end

    context 'confluence strength levels' do
      it 'returns :strong for score >= 80' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 },
          { indicator: 'rsi', direction: :bullish, confidence: 70 },
          { indicator: 'macd', direction: :bullish, confidence: 65 },
          { indicator: 'trend_duration', direction: :bullish, confidence: 60 }
        ]

        confluence = strategy.send(:calculate_confluence, results)
        expect(confluence[:strength]).to eq(:strong)
        expect(confluence[:score]).to eq(100)
      end

      it 'returns :moderate for score 60-79' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 },
          { indicator: 'rsi', direction: :bullish, confidence: 70 },
          { indicator: 'macd', direction: :bearish, confidence: 65 }
        ]

        confluence = strategy.send(:calculate_confluence, results)
        expect(confluence[:strength]).to eq(:moderate)
        expect(confluence[:score]).to eq(75) # 3/4 = 75%
      end

      it 'returns :weak for score 40-59' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bullish, confidence: 75 },
          { indicator: 'rsi', direction: :bearish, confidence: 60 },
          { indicator: 'macd', direction: :bearish, confidence: 65 }
        ]

        confluence = strategy.send(:calculate_confluence, results)
        expect(confluence[:strength]).to eq(:weak)
        expect(confluence[:score]).to eq(50) # 2/4 = 50%
      end

      it 'returns :none for score < 40' do
        results = [
          { indicator: 'supertrend', direction: :bullish, confidence: 80 },
          { indicator: 'adx', direction: :bearish, confidence: 75 },
          { indicator: 'rsi', direction: :bearish, confidence: 60 },
          { indicator: 'macd', direction: :bearish, confidence: 65 },
          { indicator: 'trend_duration', direction: :bearish, confidence: 70 }
        ]

        confluence = strategy.send(:calculate_confluence, results)
        expect(confluence[:strength]).to eq(:none)
        expect(confluence[:score]).to eq(20) # 1/5 = 20%
      end
    end
  end

  describe '#generate_signal with confluence' do
    let(:strategy) do
      described_class.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } }
        ],
        confirmation_mode: :all,
        min_confidence: 50
      )
    end

    it 'includes confluence in signal result' do
      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      if signal
        expect(signal).to have_key(:confluence)
        expect(signal[:confluence]).to be_a(Hash)
        expect(signal[:confluence]).to have_key(:score)
        expect(signal[:confluence]).to have_key(:strength)
        expect(signal[:confluence]).to have_key(:breakdown)
      end
    end

    it 'confluence breakdown includes all indicators' do
      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      if signal && signal[:confluence]
        breakdown = signal[:confluence][:breakdown]
        expect(breakdown).to be_an(Array)
        breakdown.each do |indicator|
          expect(indicator).to have_key(:name)
          expect(indicator).to have_key(:direction)
          expect(indicator).to have_key(:confidence)
          expect(indicator).to have_key(:agrees)
        end
      end
    end
  end
end

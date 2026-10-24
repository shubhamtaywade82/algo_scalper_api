# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::StrategyAdapter do
  let(:dummy_strategy) do
    Class.new do
      def initialize(series:, **_opts)
        @series = series
      end

      def generate_signal(_idx)
        { action: :buy_call, confidence: 85.0 }
      end
    end
  end

  let(:series) { double('CandleSeries', candles: [double('Candle', timestamp: Time.current)]) }

  describe '.analyze_with_strategy' do
    it 'returns bullish direction when strategy outputs buy_call' do
      result = described_class.analyze_with_strategy(
        strategy_class: dummy_strategy,
        series: series
      )

      expect(result[:status]).to eq(:ok)
      expect(result[:direction]).to eq(:bullish)
      expect(result[:confidence]).to eq(85.0)
    end
  end
end

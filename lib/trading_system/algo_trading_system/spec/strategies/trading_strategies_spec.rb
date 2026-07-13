# frozen_string_literal: true

require 'spec_helper'
require_relative '../../src/strategies/trading_strategies'

RSpec.describe TradingStrategies::StrategyFactory do
  describe '.create' do
    it 'creates an RSI MACD strategy' do
      strategy = described_class.create(:rsi_macd)
      expect(strategy).to be_a(TradingStrategies::RSIMACDReversal)
    end

    it 'raises an error for unknown strategies' do
      expect { described_class.create(:unknown) }.to raise_error(ArgumentError)
    end
  end

  describe TradingStrategies::RSIMACDReversal do
    let(:strategy) { described_class.new }

    it 'starts with HOLD signal' do
      expect(strategy.signal[:action]).to eq('HOLD')
    end
  end
end

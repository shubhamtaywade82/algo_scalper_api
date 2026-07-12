# frozen_string_literal: true

require 'spec_helper'
require_relative '../../src/backtest/options_engine'

RSpec.describe Backtest::OptionsBacktestEngine do
  let(:engine) { described_class.new(capital: 1_000_000) }

  describe '#backtest' do
    it 'initializes with capital and returns a report' do
      bars = [
        { timestamp: 1_704_080_000, open: 100, high: 105, low: 95, close: 100, volume: 1000 },
        { timestamp: 1_704_080_060, open: 100, high: 110, low: 90, close: 105, volume: 1000 }
      ]

      # Mock strategy that does nothing
      strategy = ->(_bar) { { action: 'HOLD' } }

      result = engine.backtest(symbol: 'NIFTY-CE', bars: bars, strategy: strategy)

      expect(result[:summary][:total_trades]).to eq(0)
      expect(result[:summary][:ending_capital]).to eq("₹1000000.0")
    end

    it 'executes a trade and takes profit' do
      bars = [
        { timestamp: 1_704_080_000, open: 100, high: 105, low: 95, close: 100, volume: 1000 }, # SIGNAL
        { timestamp: 1_704_080_060, open: 100, high: 105, low: 95, close: 100, volume: 1000 }, # ENTRY (close=100)
        { timestamp: 1_704_080_120, open: 100, high: 125, low: 99, close: 110, volume: 1000 }  # TP HIT
      ]

      strategy = ->(bar) do
        if bar[:timestamp] == 1_704_080_000
          { action: 'BUY', direction: 'LONG' }
        else
          { action: 'HOLD' }
        end
      end

      result = engine.backtest(symbol: 'NIFTY-CE', bars: bars, strategy: strategy)

      expect(result[:summary][:total_trades]).to eq(1)
      expect(result[:trades].first[:status]).to eq('WIN')
    end
  end
end

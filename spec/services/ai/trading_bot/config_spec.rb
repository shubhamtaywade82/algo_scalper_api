# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TradingBot::Config do
  describe '.load' do
    it 'loads with defaults when no config exists' do
      config = described_class.new
      expect(config.mode).to eq('paper')
      expect(config.symbols).to eq(%w[NIFTY BANKNIFTY])
      expect(config.paper?).to be(true)
      expect(config.live?).to be(false)
    end

    it 'accepts overrides' do
      config = described_class.new(
        mode: 'live',
        symbols: %w[RELIANCE TCS],
        max_risk_per_trade_pct: 1.5
      )

      expect(config.mode).to eq('live')
      expect(config.symbols).to eq(%w[RELIANCE TCS])
      expect(config.max_risk_per_trade_pct).to eq(1.5)
      expect(config.live?).to be(true)
    end

    it 'normalizes symbol case' do
      config = described_class.new(symbols: %w[nifty banknifty])
      expect(config.symbols).to eq(%w[NIFTY BANKNIFTY])
    end
  end

  describe '#paper?' do
    it 'returns true for paper mode' do
      config = described_class.new(mode: 'paper')
      expect(config.paper?).to be(true)
    end

    it 'returns false for live mode' do
      config = described_class.new(mode: 'live')
      expect(config.paper?).to be(false)
    end
  end

  describe '#live?' do
    it 'returns true for live mode' do
      config = described_class.new(mode: 'live')
      expect(config.live?).to be(true)
    end

    it 'returns false for paper mode' do
      config = described_class.new(mode: 'paper')
      expect(config.live?).to be(false)
    end
  end
end

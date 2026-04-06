# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GenerativeAiMarketGate do
  describe '.skip?' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        { ai: { skip_generative_ai_when_market_closed: true } }
      )
    end

    it 'returns false when force is true' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      expect(described_class.skip?(force: true)).to be false
    end

    it 'returns false when flag is off' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        { ai: { skip_generative_ai_when_market_closed: false } }
      )
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      expect(described_class.skip?(force: false)).to be false
    end

    it 'returns true when flag is on and market is closed' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      expect(described_class.skip?(force: false)).to be true
    end

    it 'returns false when flag is on and market is open' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      expect(described_class.skip?(force: false)).to be false
    end
  end

  describe '.skip_explanation' do
    it 'includes flag and market_closed state' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        { ai: { skip_generative_ai_when_market_closed: true } }
      )
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)

      expect(described_class.skip_explanation).to include('skip_generative_ai_when_market_closed=true')
      expect(described_class.skip_explanation).to include('market_closed=true')
    end
  end
end

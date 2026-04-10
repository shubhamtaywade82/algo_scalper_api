# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig do
  after { described_class.reset! }

  describe '.fetch' do
    it 'returns a hash with symbolized keys' do
      result = described_class.fetch
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it 'caches consecutive calls within TTL' do
      first = described_class.fetch
      second = described_class.fetch
      expect(first).to equal(second)
    end

    it 'returns fresh config after reset!' do
      first = described_class.fetch
      described_class.reset!
      second = described_class.fetch
      expect(first).not_to equal(second)
    end

    context 'when LIVE_TRADING env controls execution mode' do
      around do |example|
        prior = ENV.fetch('LIVE_TRADING', nil)
        example.run
        if prior.nil?
          ENV.delete('LIVE_TRADING')
        else
          ENV['LIVE_TRADING'] = prior
        end
        described_class.reset!
      end

      it 'forces paper_trading.enabled true when LIVE_TRADING is unset' do
        ENV.delete('LIVE_TRADING')
        described_class.reset!
        expect(described_class.fetch.dig(:paper_trading, :enabled)).to be(true)
      end

      it 'forces paper_trading.enabled true when LIVE_TRADING is false' do
        ENV['LIVE_TRADING'] = 'false'
        described_class.reset!
        expect(described_class.fetch.dig(:paper_trading, :enabled)).to be(true)
      end

      it 'forces paper_trading.enabled false when LIVE_TRADING is true' do
        ENV['LIVE_TRADING'] = 'true'
        described_class.reset!
        expect(described_class.fetch.dig(:paper_trading, :enabled)).to be(false)
      end
    end

    context 'when SIGNAL_TIER env applies exploratory preset' do
      around do |example|
        prior = ENV.fetch('SIGNAL_TIER', nil)
        ENV['SIGNAL_TIER'] = 'exploratory'
        example.run
        if prior.nil?
          ENV.delete('SIGNAL_TIER')
        else
          ENV['SIGNAL_TIER'] = prior
        end
        described_class.reset!
      end

      it 'relaxes direction gate and disables entry quality enforcement' do
        described_class.reset!
        cfg = described_class.fetch
        expect(cfg.dig(:signals, :signal_tier)).to eq('exploratory')
        expect(cfg.dig(:signals, :enable_direction_gate)).to be(false)
        expect(cfg.dig(:entry_quality, :enforce)).to be(false)
      end
    end

    context 'when SIGNAL_TIER env applies selective preset' do
      around do |example|
        prior = ENV.fetch('SIGNAL_TIER', nil)
        ENV['SIGNAL_TIER'] = 'selective'
        example.run
        if prior.nil?
          ENV.delete('SIGNAL_TIER')
        else
          ENV['SIGNAL_TIER'] = prior
        end
        described_class.reset!
      end

      it 'tightens validation and enables options analysis gate' do
        described_class.reset!
        cfg = described_class.fetch
        expect(cfg.dig(:signals, :signal_tier)).to eq('selective')
        expect(cfg.dig(:signals, :validation_mode)).to eq('conservative')
        expect(cfg.dig(:signals, :options_analysis_gate, :enabled)).to be(true)
        expect(cfg.dig(:signals, :halt_on_validation_failure)).to be(true)
      end
    end
  end

  describe '.mode' do
    it 'returns mode from config' do
      allow(described_class).to receive(:fetch).and_return({ mode: 'paper' })
      expect(described_class.mode).to eq('paper')
    end
  end

  describe '.event_driven_intraday_ai?' do
    it 'treats string tick_ai_analysis_enabled from DB-style JSON as enabled' do
      allow(described_class).to receive(:fetch).and_return({ signals: { tick_ai_analysis_enabled: 'true' } })
      expect(described_class.event_driven_intraday_ai?).to be(true)
    end

    it 'is true when event_driven_ai_alerts is set' do
      allow(described_class).to receive(:fetch).and_return({ signals: { event_driven_ai_alerts: true } })
      expect(described_class.event_driven_intraday_ai?).to be(true)
    end
  end
end

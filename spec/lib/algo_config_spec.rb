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

    context 'when paper trading relaxes direction gate for research' do
      around do |example|
        prior_live = ENV.fetch('LIVE_TRADING', nil)
        prior_strict = ENV.fetch('PAPER_STRICT_DIRECTION_GATE', nil)
        ENV['LIVE_TRADING'] = 'false'
        ENV.delete('PAPER_STRICT_DIRECTION_GATE')
        example.run
        if prior_live.nil?
          ENV.delete('LIVE_TRADING')
        else
          ENV['LIVE_TRADING'] = prior_live
        end
        if prior_strict.nil?
          ENV.delete('PAPER_STRICT_DIRECTION_GATE')
        else
          ENV['PAPER_STRICT_DIRECTION_GATE'] = prior_strict
        end
        described_class.reset!
      end

      it 'disables enable_direction_gate when paper mode is active' do
        described_class.reset!
        expect(described_class.fetch.dig(:signals, :enable_direction_gate)).to be(false)
      end

      it 'keeps direction gate enabled when PAPER_STRICT_DIRECTION_GATE is true' do
        ENV['PAPER_STRICT_DIRECTION_GATE'] = 'true'
        described_class.reset!
        expect(described_class.fetch.dig(:signals, :enable_direction_gate)).to be(true)
      end
    end

    context 'when signal_tier comes from the config document' do
      let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

      around do |example|
        prior_env = ENV.fetch('SIGNAL_TIER', nil)
        prior_force = ENV.fetch('SIGNAL_TIER_FORCE', nil)
        ENV.delete('SIGNAL_TIER')
        ENV.delete('SIGNAL_TIER_FORCE')
        example.run
      ensure
        prior_env.nil? ? ENV.delete('SIGNAL_TIER') : ENV['SIGNAL_TIER'] = prior_env
        prior_force.nil? ? ENV.delete('SIGNAL_TIER_FORCE') : ENV['SIGNAL_TIER_FORCE'] = prior_force
        Setting.where(key: doc_key).delete_all
        described_class.reset!
      end

      def seed_tier(tier)
        Setting.put(doc_key, { signals: { signal_tier: tier } }.to_json)
        described_class.reset!
      end

      it 'applies the selective preset when the document selects it' do
        seed_tier('selective')
        cfg = described_class.fetch
        expect(cfg.dig(:signals, :signal_tier)).to eq('selective')
        expect(cfg.dig(:signals, :validation_mode)).to eq('conservative')
        expect(cfg.dig(:signals, :options_analysis_gate, :enabled)).to be(true)
        expect(cfg.dig(:signals, :halt_on_validation_failure)).to be(true)
      end

      it 'applies the exploratory preset when the document selects it' do
        seed_tier('exploratory')
        cfg = described_class.fetch
        expect(cfg.dig(:signals, :signal_tier)).to eq('exploratory')
        expect(cfg.dig(:entry_quality, :enforce)).to be(true)
        expect(cfg.dig(:entry_quality, :min_score)).to eq(38)
      end

      it 'ignores a divergent SIGNAL_TIER env without SIGNAL_TIER_FORCE' do
        seed_tier('selective')
        ENV['SIGNAL_TIER'] = 'exploratory'
        described_class.reset!
        expect(Rails.logger).to receive(:warn).with(/SIGNAL_TIER=exploratory ignored/).at_least(:once)
        expect(described_class.fetch.dig(:signals, :signal_tier)).to eq('selective')
      end

      it 'honors SIGNAL_TIER env when SIGNAL_TIER_FORCE is true' do
        seed_tier('selective')
        ENV['SIGNAL_TIER'] = 'exploratory'
        ENV['SIGNAL_TIER_FORCE'] = 'true'
        described_class.reset!
        cfg = described_class.fetch
        expect(cfg.dig(:entry_quality, :min_score)).to eq(38)
      end
    end
  end

  describe '.mode' do
    it 'returns mode from config' do
      allow(described_class).to receive(:fetch).and_return({ mode: 'paper' })
      expect(described_class.mode).to eq('paper')
    end
  end

  describe '.position_snapshot' do
    let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

    around do |example|
      prior_live = ENV.fetch('LIVE_TRADING', nil)
      ENV['LIVE_TRADING'] = 'false'
      example.run
    ensure
      prior_live.nil? ? ENV.delete('LIVE_TRADING') : ENV['LIVE_TRADING'] = prior_live
      Setting.where(key: doc_key).delete_all
      described_class.reset!
    end

    it 'returns effective config minus credential sections' do
      Setting.put(
        doc_key,
        {
          risk: { sl_pct: 0.02 },
          signals: { signal_tier: 'standard' },
          dhanhq: { client_id: 'secret' },
          telegram: { bot_token: 'secret' },
          ai: { enabled: true }
        }.to_json
      )
      described_class.reset!

      snapshot = described_class.position_snapshot

      expect(snapshot).to include(:risk, :signals)
      expect(snapshot.keys).not_to include(:dhanhq, :telegram, :ai)
    end

    it 'reflects document changes after reset' do
      Setting.put(doc_key, { risk: { sl_pct: 0.02 } }.to_json)
      described_class.reset!
      first = described_class.position_snapshot.dig(:risk, :sl_pct)

      Setting.put(doc_key, { risk: { sl_pct: 0.05 } }.to_json)
      described_class.reset!
      second = described_class.position_snapshot.dig(:risk, :sl_pct)

      expect(first).to eq(0.02)
      expect(second).to eq(0.05)
    end
  end

  describe '.version' do
    it 'returns a content hash and the latest change-log id' do
      version = described_class.version
      expect(version[:hash]).to be_a(String).and(be_present)
      expect(version).to have_key(:change_log_id)
    end

    it 'changes the hash when the effective config changes' do
      allow(described_class).to receive(:fetch).and_return({ a: 1 })
      first = described_class.version[:hash]
      allow(described_class).to receive(:fetch).and_return({ a: 2 })
      expect(described_class.version[:hash]).not_to eq(first)
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

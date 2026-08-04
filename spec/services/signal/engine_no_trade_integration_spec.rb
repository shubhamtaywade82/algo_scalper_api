# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine, 'No-Trade Engine Integration' do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end

  let(:nifty_instrument) { create(:instrument, :nifty_index) }
  let(:bars_1m) { build(:candle_series, symbol: 'NIFTY', interval: '1') }
  let(:bars_5m) { build(:candle_series, symbol: 'NIFTY', interval: '5') }

  before do
    # Add candles to series
    20.times do |i|
      bars_1m.add_candle(build(:candle, timestamp: i.minutes.ago))
      bars_5m.add_candle(build(:candle, timestamp: (i * 5).minutes.ago))
    end

    # Mock IndexInstrumentCache
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)

    # Mock market session
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)

    # Mock instrument methods
    allow(nifty_instrument).to receive(:candle_series).with(interval: '1').and_return(bars_1m)
    allow(nifty_instrument).to receive(:candle_series).with(interval: '5').and_return(bars_5m)

    # Mock AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return({
                                                      signals: {
                                                        primary_timeframe: '5m',
                                                        enable_supertrend_signal: true,
                                                        supertrend: { period: 7, multiplier: 3.0 },
                                                        adx: { min_strength: 18.0 }
                                                      }
                                                    })

    # Mock signal generation (to focus on No-Trade Engine)
    allow_any_instance_of(Indicators::Supertrend).to receive(:call).and_return({
                                                                                 trend: :bullish,
                                                                                 last_value: 25_000
                                                                               })
    allow(nifty_instrument).to receive_messages(expiry_list: [Time.zone.today + 7.days], fetch_option_chain: {
                                                  ce: { '25000' => { 'oi' => 1000, 'iv' => 15.0,
                                                                     'bid' => 100.0, 'ask' => 101.0 } },
                                                  pe: { '25000' => { 'oi' => 2000, 'iv' => 14.0,
                                                                     'bid' => 90.0, 'ask' => 91.0 } }
                                                }, adx: 20.0)

    # Mock strike selection
    allow(Options::ChainAnalyzer).to receive(:pick_strikes).and_return([
                                                                         { symbol: 'NIFTY25000CE',
                                                                           security_id: '50074', segment: 'NSE_FNO', ltp: 100.0, lot_size: 75 }
                                                                       ])

    # Mock EntryGuard (to prevent actual entry)
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)

    Signal::StateTracker.reset(index_cfg[:key])
  end

  after do
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  describe 'Phase 1: Quick No-Trade Pre-Check' do
    context 'when Phase 1 blocks the trade' do
      it 'does not proceed to signal generation' do
        # Mock Phase 1 to return blocked
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: false,
                                                                                 score: 3,
                                                                                 reasons: ['Avoid first 3 minutes',
                                                                                           'Low volatility: 10m range < 0.1%', 'IV too low'],
                                                                                 option_chain_data: nil,
                                                                                 bars_1m: nil
                                                                               })

        expect(described_class).not_to receive(:analyze_timeframe)
        expect(Rails.logger).to receive(:warn).with(match(/NO-TRADE pre-check blocked/))

        described_class.run_for(index_cfg)
      end

      it 'logs the blocking reasons' do
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: false,
                                                                                 score: 3,
                                                                                 reasons: ['Reason 1', 'Reason 2',
                                                                                           'Reason 3'],
                                                                                 option_chain_data: nil,
                                                                                 bars_1m: nil
                                                                               })

        expect(Rails.logger).to receive(:warn).with(match(%r{score=3/11}))
        expect(Rails.logger).to receive(:warn).with(match(/Reason 1/))

        described_class.run_for(index_cfg)
      end
    end

    context 'when Phase 1 allows the trade' do
      it 'proceeds to signal generation' do
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 1,
                                                                                 reasons: ['Weak trend: ADX < 15'],
                                                                                 option_chain_data: { ce: {}, pe: {} },
                                                                                 bars_1m: bars_1m
                                                                               })

        expect(described_class).to receive(:analyze_timeframe).at_least(:once)

        described_class.run_for(index_cfg)
      end

      it 'caches option chain data for Phase 2' do
        cached_option_chain = { ce: {}, pe: {} }
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 0,
                                                                                 reasons: [],
                                                                                 option_chain_data: cached_option_chain,
                                                                                 bars_1m: bars_1m
                                                                               })

        expect(described_class).to receive(:validate_no_trade_conditions).with(
          hash_including(cached_option_chain: cached_option_chain)
        )

        described_class.run_for(index_cfg)
      end

      it 'caches bars_1m for Phase 2' do
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 0,
                                                                                 reasons: [],
                                                                                 option_chain_data: {},
                                                                                 bars_1m: bars_1m
                                                                               })

        expect(described_class).to receive(:validate_no_trade_conditions).with(
          hash_including(cached_bars_1m: bars_1m)
        )

        described_class.run_for(index_cfg)
      end
    end
  end

  describe 'Phase 2: Detailed No-Trade Validation' do
    before do
      # Phase 1 passes
      allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                               allowed: true,
                                                                               score: 0,
                                                                               reasons: [],
                                                                               option_chain_data: { ce: {}, pe: {} },
                                                                               bars_1m: bars_1m
                                                                             })
    end

    context 'when Phase 2 blocks the trade' do
      it 'does not proceed to EntryGuard' do
        allow(described_class).to receive(:validate_no_trade_conditions).and_return({
                                                                                      allowed: false,
                                                                                      score: 3,
                                                                                      reasons: ['Weak trend: ADX < 15',
                                                                                                'DI overlap: no directional strength', 'No BOS in last 10m']
                                                                                    })

        expect(Entries::EntryGuard).not_to receive(:try_enter)
        expect(Rails.logger).to receive(:warn).with(match(/NO-TRADE detailed validation blocked/))

        described_class.run_for(index_cfg)
      end

      it 'logs the blocking reasons' do
        allow(described_class).to receive(:validate_no_trade_conditions).and_return({
                                                                                      allowed: false,
                                                                                      score: 3,
                                                                                      reasons: ['Reason 1', 'Reason 2',
                                                                                                'Reason 3']
                                                                                    })

        expect(Rails.logger).to receive(:warn).with(match(%r{score=3/11}))
        expect(Rails.logger).to receive(:warn).with(match(/Reason 1/))

        described_class.run_for(index_cfg)
      end
    end

    context 'when Phase 2 allows the trade' do
      it 'proceeds to EntryGuard' do
        allow(described_class).to receive(:validate_no_trade_conditions).and_return({
                                                                                      allowed: true,
                                                                                      score: 1,
                                                                                      reasons: ['Weak trend: ADX < 15']
                                                                                    })

        expect(Entries::EntryGuard).to receive(:try_enter).at_least(:once)

        described_class.run_for(index_cfg)
      end

      it 'reuses cached option chain from Phase 1' do
        cached_option_chain = { ce: {}, pe: {} }
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 0,
                                                                                 reasons: [],
                                                                                 option_chain_data: cached_option_chain,
                                                                                 bars_1m: bars_1m
                                                                               })

        expect(described_class).to receive(:validate_no_trade_conditions).with(
          hash_including(cached_option_chain: cached_option_chain)
        )

        described_class.run_for(index_cfg)
      end

      it 'reuses cached bars_1m from Phase 1' do
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 0,
                                                                                 reasons: [],
                                                                                 option_chain_data: {},
                                                                                 bars_1m: bars_1m
                                                                               })

        expect(described_class).to receive(:validate_no_trade_conditions).with(
          hash_including(cached_bars_1m: bars_1m)
        )

        described_class.run_for(index_cfg)
      end
    end
  end

  describe 'End-to-End Flow' do
    it 'executes complete flow when both phases pass' do
      # Phase 1 passes

      # Phase 2 passes
      allow(described_class).to receive_messages(quick_no_trade_precheck: {
                                                   allowed: true,
                                                   score: 0,
                                                   reasons: [],
                                                   option_chain_data: { ce: {}, pe: {} },
                                                   bars_1m: bars_1m
                                                 }, validate_no_trade_conditions: {
                                                   allowed: true,
                                                   score: 1,
                                                   reasons: ['Weak trend: ADX < 15']
                                                 })

      # Verify complete flow
      expect(described_class).to receive(:quick_no_trade_precheck).once
      expect(described_class).to receive(:analyze_timeframe).at_least(:once)
      expect(Options::ChainAnalyzer).to receive(:pick_strikes).once
      expect(described_class).to receive(:validate_no_trade_conditions).once
      expect(Entries::EntryGuard).to receive(:try_enter).once

      described_class.run_for(index_cfg)
    end

    it 'stops early when Phase 1 blocks' do
      allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                               allowed: false,
                                                                               score: 3,
                                                                               reasons: ['Blocked'],
                                                                               option_chain_data: nil,
                                                                               bars_1m: nil
                                                                             })

      # Should not proceed to signal generation or Phase 2
      expect(described_class).not_to receive(:analyze_timeframe)
      expect(Options::ChainAnalyzer).not_to receive(:pick_strikes)
      expect(described_class).not_to receive(:validate_no_trade_conditions)
      expect(Entries::EntryGuard).not_to receive(:try_enter)

      described_class.run_for(index_cfg)
    end

    it 'stops after signal generation when Phase 2 blocks' do
      # Phase 1 passes

      # Phase 2 blocks
      allow(described_class).to receive_messages(quick_no_trade_precheck: {
                                                   allowed: true,
                                                   score: 0,
                                                   reasons: [],
                                                   option_chain_data: { ce: {}, pe: {} },
                                                   bars_1m: bars_1m
                                                 }, validate_no_trade_conditions: {
                                                   allowed: false,
                                                   score: 3,
                                                   reasons: ['Blocked']
                                                 })

      # Should generate signal but not proceed to entry
      expect(described_class).to receive(:analyze_timeframe).at_least(:once)
      expect(Options::ChainAnalyzer).to receive(:pick_strikes).once
      expect(Entries::EntryGuard).not_to receive(:try_enter)

      described_class.run_for(index_cfg)
    end
  end

  describe 'Error Handling' do
    context 'when Phase 1 pre-check raises error' do
      it 'allows trade to proceed (fail-open)' do
        allow(described_class).to receive(:quick_no_trade_precheck).and_raise(StandardError.new('Phase 1 error'))

        expect(Rails.logger).to receive(:error).with(match(/Quick No-Trade pre-check failed/))
        expect(described_class).to receive(:analyze_timeframe).at_least(:once)

        described_class.run_for(index_cfg)
      end
    end

    context 'when Phase 2 validation raises error' do
      before do
        allow(described_class).to receive(:quick_no_trade_precheck).and_return({
                                                                                 allowed: true,
                                                                                 score: 0,
                                                                                 reasons: [],
                                                                                 option_chain_data: {},
                                                                                 bars_1m: bars_1m
                                                                               })
      end

      it 'allows trade to proceed (fail-open)' do
        allow(described_class).to receive(:validate_no_trade_conditions).and_raise(StandardError.new('Phase 2 error'))

        expect(Rails.logger).to receive(:error).with(match(/No-Trade Engine validation failed/))
        expect(Entries::EntryGuard).to receive(:try_enter).at_least(:once)

        described_class.run_for(index_cfg)
      end
    end
  end
end

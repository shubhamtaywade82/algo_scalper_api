# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DirectionGate do
  describe '.allow?' do
    context 'when regime is bearish' do
      it 'blocks CE trades' do
        expect(described_class.allow?(regime: :bearish, side: :CE)).to be false
      end

      it 'allows PE trades' do
        expect(described_class.allow?(regime: :bearish, side: :PE)).to be true
      end
    end

    context 'when regime is bullish' do
      it 'allows CE trades' do
        expect(described_class.allow?(regime: :bullish, side: :CE)).to be true
      end

      it 'blocks PE trades' do
        expect(described_class.allow?(regime: :bullish, side: :PE)).to be false
      end
    end

    context 'when regime is neutral' do
      it 'blocks CE trades' do
        expect(described_class.allow?(regime: :neutral, side: :CE)).to be false
      end

      it 'blocks PE trades' do
        expect(described_class.allow?(regime: :neutral, side: :PE)).to be false
      end
    end

    context 'with string inputs' do
      it 'handles string regime' do
        expect(described_class.allow?(regime: 'bearish', side: :CE)).to be false
        expect(described_class.allow?(regime: 'bullish', side: :CE)).to be true
      end

      it 'handles string side' do
        expect(described_class.allow?(regime: :bearish, side: 'CE')).to be false
        expect(described_class.allow?(regime: :bearish, side: 'PE')).to be true
      end

      it 'handles lowercase side' do
        expect(described_class.allow?(regime: :bearish, side: 'ce')).to be false
        expect(described_class.allow?(regime: :bearish, side: 'pe')).to be true
      end
    end

    context 'with nil inputs' do
      it 'treats nil regime as neutral (blocks all)' do
        expect(described_class.allow?(regime: nil, side: :CE)).to be false
        expect(described_class.allow?(regime: nil, side: :PE)).to be false
      end
    end

    context 'with invalid regime' do
      it 'treats unknown regime as neutral (blocks all)' do
        expect(described_class.allow?(regime: :unknown, side: :CE)).to be false
        expect(described_class.allow?(regime: :sideways, side: :PE)).to be false
      end
    end
  end

  describe '.blocked?' do
    it 'blocks CE in bearish regime' do
      expect(described_class.blocked?(regime: :bearish, side: :CE)).to be true
    end

    it 'allows PE in bearish regime' do
      expect(described_class.blocked?(regime: :bearish, side: :PE)).to be false
    end

    it 'allows CE in bullish regime' do
      expect(described_class.blocked?(regime: :bullish, side: :CE)).to be false
    end

    it 'blocks PE in bullish regime' do
      expect(described_class.blocked?(regime: :bullish, side: :PE)).to be true
    end

    it 'blocks CE in neutral regime' do
      expect(described_class.blocked?(regime: :neutral, side: :CE)).to be true
    end

    it 'blocks PE in neutral regime' do
      expect(described_class.blocked?(regime: :neutral, side: :PE)).to be true
    end
  end

  describe 'logging' do
    it 'logs when a trade is blocked' do
      allow(Rails.logger).to receive(:info)

      described_class.allow?(regime: :bearish, side: :CE)

      expect(Rails.logger).to have_received(:info).with(
        '[DirectionGate] blocked CE in bearish regime'
      )
    end

    it 'does not log when a trade is allowed' do
      allow(Rails.logger).to receive(:info)

      described_class.allow?(regime: :bearish, side: :PE)

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe 'integration with Signal::Engine', :integration do
    let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I' } }

    context 'when regime is bearish and direction is bullish (CE trade)' do
      let(:mock_instrument) { instance_double(Instrument) }
      let(:mock_15m_series) { instance_double(CandleSeries) }
      let(:mock_candle) { instance_double(Candle, close: 100, timestamp: Time.current) }
      let(:mock_series) do
        instance_double(CandleSeries, candles: [mock_candle])
      end

      before do
        # Mock regime resolver to return bearish
        allow(Market::MarketRegimeResolver).to receive(:resolve).and_return(:bearish)

        # Mock Signal::Engine.analyze_timeframe to return bullish signal
        allow(Signal::Engine).to receive(:analyze_timeframe).and_return(
          status: :ok,
          series: mock_series,
          supertrend: { trend: :bullish, last_value: 100.0 },
          adx_value: 25.0,
          direction: :bullish,
          last_candle_timestamp: Time.current
        )

        # Mock instrument to provide 15m candles for regime check
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch)
          .and_return(mock_instrument)
        allow(mock_instrument).to receive(:candle_series)
          .with(interval: '15')
          .and_return(mock_15m_series)
        allow(mock_15m_series).to receive(:candles)
          .and_return([{ open: 100, high: 105, low: 99, close: 102 }] * 25)

        regime_detector = instance_double(MarketRegimeDetector, detect: { regime: 'TRENDING_DOWN', confidence: 80 })
        allow(MarketRegimeDetector).to receive(:new).and_return(regime_detector)

        allow(Market::Calendar).to receive(:trading_day_today?).and_return(true)
        ist = Time.zone.parse('2026-04-06 10:30:00')
        allow(TradingSession::Service).to receive_messages(market_closed?: false, current_ist_time: ist)

        # Stub AlgoConfig
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: {
            entry_strategy: { primary: 'legacy' },
            primary_timeframe: '5m',
            confirmation_timeframe: nil,
            enable_confirmation_timeframe: false,
            halt_on_validation_failure: false,
            enable_direction_gate: true,
            enable_index_ta: false,
            enable_index_ta_filter: false,
            use_strategy_recommendations: false,
            supertrend: { period: 7, multiplier: 3 },
            adx: { min_strength: 20 },
            enable_adx_filter: true,
            enable_smc_avrz_permission: false,
            enable_no_trade_engine: false,
            validation_mode: :balanced,
            validation_modes: {
              balanced: {
                require_iv_rank_check: false,
                require_theta_risk_check: false,
                require_trend_confirmation: false,
                adx_min_strength: 15
              },
              conservative: {
                require_iv_rank_check: false,
                require_theta_risk_check: false,
                require_trend_confirmation: false,
                adx_min_strength: 15
              }
            }
          }
        )

        # Stub Signal::StateTracker
        allow(Signal::StateTracker).to receive(:reset)
        allow(Signal::StateTracker).to receive(:record)
          .and_return({ count: 1, multiplier: 1 })
      end

      it 'does NOT invoke Options::ChainAnalyzer (SMC downstream)' do
        # Spy on Options::ChainAnalyzer to ensure it's NOT called
        allow(Options::ChainAnalyzer).to receive(:pick_strikes)

        Signal::Engine.run_for(index_cfg)

        expect(Options::ChainAnalyzer).not_to have_received(:pick_strikes)
      end

      it 'logs the block reason' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:debug)
        allow(Rails.logger).to receive(:error)

        Signal::Engine.run_for(index_cfg)

        expect(Rails.logger).to have_received(:info).with(
          /DirectionGate BLOCKED NIFTY: Counter-trend trade\. CE requested vs TRENDING_DOWN/
        )
      end

      it 'resets signal state tracker' do
        Signal::Engine.run_for(index_cfg)

        expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
      end
    end

    context 'when regime is CHOPPY and selling strategies are disabled (regression: position_side leak)' do
      let(:mock_instrument) { instance_double(Instrument) }
      let(:mock_series) { instance_double(CandleSeries, candles: [instance_double(Candle, close: 100, timestamp: Time.current)], atr: 25.0) }

      before do
        allow(Signal::Engine).to receive(:analyze_timeframe).and_return(
          status: :ok,
          series: mock_series,
          supertrend: { trend: :bullish, last_value: 100.0 },
          adx_value: 25.0,
          direction: :bullish,
          last_candle_timestamp: Time.current
        )

        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(mock_instrument)

        regime_detector = instance_double(MarketRegimeDetector, detect: { regime: 'CHOPPY', confidence: 60 })
        allow(MarketRegimeDetector).to receive(:new).and_return(regime_detector)

        allow(Market::Calendar).to receive(:trading_day_today?).and_return(true)
        ist = Time.zone.parse('2026-04-06 10:30:00')
        allow(TradingSession::Service).to receive_messages(market_closed?: false, current_ist_time: ist)

        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: {
            entry_strategy: { primary: 'legacy' },
            primary_timeframe: '5m',
            confirmation_timeframe: nil,
            enable_confirmation_timeframe: false,
            halt_on_validation_failure: false,
            enable_direction_gate: true,
            enable_index_ta: false,
            enable_index_ta_filter: false,
            use_strategy_recommendations: false,
            supertrend: { period: 7, multiplier: 3 },
            adx: { min_strength: 20 },
            enable_adx_filter: true,
            enable_smc_avrz_permission: false,
            enable_no_trade_engine: false,
            validation_mode: :balanced,
            validation_modes: {
              balanced: { require_iv_rank_check: false, require_theta_risk_check: false, require_trend_confirmation: false, adx_min_strength: 15 },
              conservative: { require_iv_rank_check: false, require_theta_risk_check: false, require_trend_confirmation: false, adx_min_strength: 15 }
            }
            # no strategies_enabled key -> RegimeStrategyRouter#selling_enabled? is false
          }
        )

        allow(Signal::StateTracker).to receive_messages(reset: nil, record: { count: 1, multiplier: 1 })
        allow(Signal::ValidationGates).to receive(:comprehensive_validation).and_return(valid: true, reason: nil)
        allow(Entries::EntryFilterEngine).to receive(:new).and_return(instance_double(Entries::EntryFilterEngine, valid_entry?: true))
        allow(Trading::PermissionResolver).to receive(:resolve).and_return(:scale_ready)
        allow(Signal::MomentumValidator).to receive(:validate).and_return(instance_double(Signal::MomentumValidator::Result, score: 2))
        allow(TradingSignal).to receive(:create_from_analysis)
        allow(Signal::ExpiryGate).to receive_messages(expiry_trade_allowed?: true, resolve_nearest_expiry_date: nil)
        allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return(
          Options::ChainAnalyzer::StrikePickResult.new(
            [{ symbol: 'NIFTY-X-CE', security_id: '1', segment: 'IDX_I', derivative_id: 1, lot_size: 75 }], nil, nil
          )
        )
        allow(Entries::BosEntryEngine).to receive(:run_for)
        allow(Entries::EntryGuard).to receive(:try_enter)
      end

      it 'routes through the normal BosEntryEngine, NOT the direct-entry shortcut meant for supertrend/selling' do
        Signal::Engine.run_for(index_cfg)

        expect(Entries::BosEntryEngine).to have_received(:run_for)
        expect(Entries::EntryGuard).not_to have_received(:try_enter)
      end
    end
  end
end

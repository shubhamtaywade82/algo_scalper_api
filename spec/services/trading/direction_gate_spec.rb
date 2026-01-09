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

        # Stub AlgoConfig
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: {
            enable_index_ta: false,
            use_strategy_recommendations: false,
            supertrend: { period: 7, multiplier: 3 },
            adx: { min_strength: 20 },
            enable_adx_filter: true
          }
        )

        # Stub TradingSession to return market open
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)

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
          /DirectionGate BLOCKED.*NIFTY.*CE.*bearish/
        )
      end

      it 'resets signal state tracker' do
        Signal::Engine.run_for(index_cfg)

        expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
      end
    end
  end
end

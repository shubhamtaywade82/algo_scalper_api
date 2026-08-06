# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine, :vcr do
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

  before do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)
    allow(nifty_instrument).to receive(:intraday_ohlc).and_wrap_original do |original_method, **kwargs|
      kwargs[:days] = 7 unless kwargs.key?(:days) || kwargs.key?(:from_date)
      original_method.call(**kwargs)
    end

    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  after do
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  describe '.analyze_with_multi_indicators' do
    let(:signals_cfg) do
      {
        primary_timeframe: '5m',
        use_multi_indicator_strategy: true,
        confirmation_mode: :all,
        min_confidence: 60,
        indicators: [
          {
            type: 'supertrend',
            enabled: true,
            config: {
              period: 7,
              multiplier: 3.0
            }
          },
          {
            type: 'adx',
            enabled: true,
            config: {
              period: 14,
              min_strength: 18
            }
          }
        ]
      }
    end

    let(:mock_candles) do
      base = 22_000.0
      Array.new(50) do |i|
        price = base + (i * 5.0) + rand(-10.0..10.0)
        double("Candle#{i}",
               open: price, high: price + 20, low: price - 20, close: price + 5,
               volume: 100_000 + (i * 1000), timestamp: Time.current - (50 - i).minutes)
      end
    end
    let(:mock_series) do
      series = double('CandleSeries')
      allow(series).to receive_messages(candles: mock_candles, size: mock_candles.size, last: mock_candles.last, symbol: 'NIFTY', interval: '5')
      series
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
                                                        signals: signals_cfg.merge(
                                                          supertrend: { period: 7, multiplier: 3.0 },
                                                          adx: { min_strength: 18 }
                                                        )
                                                      })
    end

    context 'when indicators are enabled' do
      before do
        allow(nifty_instrument).to receive(:candle_series).and_return(mock_series)
      end

      it 'builds MultiIndicatorStrategy with configured indicators' do
        expect(MultiIndicatorStrategy).to receive(:new).with(
          hash_including(
            series: anything,
            indicators: array_including(
              hash_including(type: 'supertrend'),
              hash_including(type: 'adx')
            ),
            confirmation_mode: :all,
            min_confidence: 60
          )
        ).and_call_original

        described_class.send(:analyze_with_multi_indicators,
                             index_cfg: index_cfg,
                             instrument: nifty_instrument,
                             timeframe: '5m',
                             signals_cfg: signals_cfg)
      end

      it 'returns analysis result with status :ok' do
        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:status]).to eq(:ok)
        expect(result).to have_key(:series)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:supertrend)
        expect(result).to have_key(:adx_value)
      end

      it 'converts signal type to direction' do
        allow_any_instance_of(MultiIndicatorStrategy).to receive(:generate_signal).and_return(
          { type: :ce, confidence: 75 }
        )

        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:direction]).to eq(:bullish)
      end

      it 'returns :avoid when no signal generated' do
        allow_any_instance_of(MultiIndicatorStrategy).to receive(:generate_signal).and_return(nil)

        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:direction]).to eq(:avoid)
        expect(result[:status]).to eq(:ok)
      end
    end

    context 'when no indicators are enabled' do
      let(:signals_cfg) do
        {
          primary_timeframe: '5m',
          use_multi_indicator_strategy: true,
          indicators: [
            { type: 'supertrend', enabled: false },
            { type: 'adx', enabled: false }
          ]
        }
      end

      it 'returns error status' do
        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to eq('No enabled indicators')
      end
    end

    context 'when timeframe is invalid' do
      it 'returns error status' do
        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: 'invalid',
                                      signals_cfg: signals_cfg)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to match(/Invalid timeframe/)
      end
    end

    context 'when no candle data available' do
      before do
        allow(nifty_instrument).to receive(:candle_series).and_return(nil)
      end

      it 'returns no_data status' do
        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:status]).to eq(:no_data)
        expect(result[:message]).to match(/No candle data/)
      end
    end

    context 'with per-index ADX thresholds' do
      let(:index_cfg_with_adx) do
        index_cfg.merge(
          adx_thresholds: {
            primary_min_strength: 25
          }
        )
      end

      before do
        allow(nifty_instrument).to receive(:candle_series).and_return(mock_series)
      end

      it 'updates ADX indicator config with per-index threshold' do
        expect(MultiIndicatorStrategy).to receive(:new).with(
          hash_including(
            indicators: array_including(
              hash_including(
                type: 'adx',
                config: hash_including(min_strength: 25)
              )
            )
          )
        ).and_call_original

        described_class.send(:analyze_with_multi_indicators,
                             index_cfg: index_cfg_with_adx,
                             instrument: nifty_instrument,
                             timeframe: '5m',
                             signals_cfg: signals_cfg)
      end
    end

    context 'when error occurs' do
      before do
        allow(nifty_instrument).to receive(:candle_series).and_raise(StandardError, 'Test error')
      end

      it 'handles error gracefully' do
        expect(Rails.logger).to receive(:error).with(match(/Multi-indicator analysis failed/))

        result = described_class.send(:analyze_with_multi_indicators,
                                      index_cfg: index_cfg,
                                      instrument: nifty_instrument,
                                      timeframe: '5m',
                                      signals_cfg: signals_cfg)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to eq('Test error')
      end
    end
  end

  describe '.run_for with multi-indicator system' do
    let(:signals_cfg) do
      {
        primary_timeframe: '5m',
        use_multi_indicator_strategy: true,
        confirmation_mode: :all,
        min_confidence: 60,
        enable_confirmation_timeframe: false,
        supertrend: { period: 7, multiplier: 3.0 },
        adx: { min_strength: 18 },
        indicators: [
          {
            type: 'supertrend',
            enabled: true,
            config: { period: 7, multiplier: 3.0 }
          },
          {
            type: 'adx',
            enabled: true,
            config: { period: 14, min_strength: 18 }
          }
        ],
        validation_mode: 'aggressive',
        validation_modes: {
          aggressive: {
            require_iv_rank_check: false,
            require_theta_risk_check: false,
            require_trend_confirmation: false
          }
        }
      }
    end

    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: signals_cfg })
      empty_strikes = Options::ChainAnalyzer::StrikePickResult.new(
        [],
        'strike_selector_blocked',
        'StrikeSelector: test [NIFTY]'
      )
      allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return(empty_strikes)
      allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    end

    it 'uses multi-indicator system when enabled' do
      expect(described_class).to receive(:analyze_with_multi_indicators).and_call_original
      expect(described_class).not_to receive(:analyze_timeframe)

      described_class.run_for(index_cfg)
    end

    context 'when multi-indicator system is disabled' do
      let(:signals_cfg) do
        {
          primary_timeframe: '5m',
          use_multi_indicator_strategy: false,
          enable_supertrend_signal: true,
          supertrend: { period: 7, multiplier: 3.0 },
          adx: { min_strength: 18 }
        }
      end

      it 'falls back to traditional analysis' do
        expect(described_class).not_to receive(:analyze_with_multi_indicators)
        expect(described_class).to receive(:analyze_timeframe).and_call_original

        described_class.run_for(index_cfg)
      end
    end
  end
end

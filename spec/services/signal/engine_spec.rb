# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.execute_options_analysis' do
    subject(:options_analysis) do
      described_class.send(
        :execute_options_analysis,
        index_cfg,
        expiry_date: expiry_date,
        expiry_blocked: expiry_blocked,
        primary_analysis: primary_analysis
      )
    end

    let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
    let(:expiry_date) { Date.new(2026, 7, 10) }
    let(:expiry_blocked) { false }
    let(:primary_analysis) { { direction: :bullish } }

    context 'when cached chain data is available for the expiry' do
      let(:chain_data) do
        {
          last_price: 23_000.0,
          oc: {
            '23000' => {
              'ce' => { 'implied_volatility' => 12.5, 'greeks' => { 'theta' => -45.2 } },
              'pe' => { 'implied_volatility' => 18.0, 'greeks' => { 'theta' => -30.1 } }
            }
          }
        }
      end

      before do
        instrument = instance_double(Instrument, fetch_option_chain: chain_data)
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
        allow(Options::GammaRampDetector).to receive(:new).and_return(instance_double(Options::GammaRampDetector, gamma_pressure_score: 0.35, ramp_strike: { strike: 23_100.0 }))
        allow(Options::IvRankTracker.instance).to receive(:percentile_rank).and_return(0.42)
      end

      it 'populates gamma_pressure with real score and matching strike' do
        expect(options_analysis[:gamma_pressure][:score]).to eq(0.35)
        expect(options_analysis[:gamma_pressure][:strike]).to eq(23_100.0)
        expect(options_analysis[:gamma_pressure][:implemented]).to be true
      end

      it 'populates iv_rank with a real proxy from IvRankTracker' do
        expect(options_analysis[:iv_rank][:valid]).to be true
        expect(options_analysis[:iv_rank][:iv_rank_proxy]).to eq(0.42)
        expect(options_analysis[:iv_rank][:implemented]).to be true
      end

      it 'populates theta_risk with real theta when greeks present' do
        expect(options_analysis[:theta_risk][:valid]).to be true
        expect(options_analysis[:theta_risk][:risk_score]).to eq(-45.2)
        expect(options_analysis[:theta_risk][:implemented]).to be true
      end

      it 'passes through expiry_blocked and expiry_date' do
        expect(options_analysis[:expiry_blocked]).to be false
        expect(options_analysis[:expiry_date]).to eq(expiry_date)
      end

      it 'includes chain_data' do
        expect(options_analysis[:chain_data]).to eq(chain_data)
      end
    end

    context 'when no reachable chain/IV data exists' do
      let(:primary_analysis) { { direction: :bearish } }

      before do
        instrument = instance_double(Instrument, fetch_option_chain: nil)
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
        allow(Options::GammaRampDetector).to receive(:new).and_return(instance_double(Options::GammaRampDetector, gamma_pressure_score: 0.0, ramp_strike: nil))
        allow(Options::IvRankTracker.instance).to receive(:percentile_rank).and_return(nil)
      end

      it 'returns honest fallbacks with implemented flags' do
        expect(options_analysis[:expiry_date]).to eq(expiry_date)
        expect(options_analysis[:expiry_blocked]).to be false
        expect(options_analysis[:chain_data]).to be_nil
        expect(options_analysis[:gamma_pressure]).to eq({ score: nil, strike: nil, implemented: false })
        expect(options_analysis[:iv_rank]).to eq({ valid: true, iv_rank_proxy: nil, implemented: false })
        expect(options_analysis[:theta_risk]).to eq({ valid: true, risk_score: nil, implemented: false })
      end
    end
  end

  describe '.stock_quality_result' do
    let(:primary_analysis) { { series: series, adx_value: 28.0 } }
    let(:primary_series) { series }
    let(:result) do
      described_class.send(:stock_quality_result, primary_analysis: primary_analysis, primary_series: primary_series)
    end

    context 'with a strong trending series' do
      let(:candles) do
        Array.new(40) do |i|
          close = if i >= 30
                    100.0 + ((i - 30) * 2.0)
                  else
                    100.0 - (30 - i).to_f
                  end
          OpenStruct.new(
            timestamp: Time.zone.at(i * 60),
            open: close,
            high: close + 0.5,
            low: close - 0.5,
            close: close,
            volume: 1000 + (i * 10)
          )
        end
      end
      let(:series) { instance_double(CandleSeries, candles: candles, closes: candles.map(&:close), atr: 20.0) }

      it 'returns a numeric score between 0 and 100' do
        score = result[:score]
        expect(score).to be_a(Numeric)
        expect(score).to be >= 0
        expect(score).to be <= 100
      end

      it 'returns true for pass when trend is strong' do
        expect(result[:pass]).to be true
      end

      it 'includes all breakdown keys' do
        breakdown = result[:breakdown]
        expect(breakdown).to include(stock_mode: true, adx_score: kind_of(Float), atr_score: kind_of(Float), candle_quality_score: kind_of(Float), implemented: true)
      end

      it 'marks breakdown as implemented' do
        expect(result[:breakdown][:implemented]).to be true
      end
    end
  end
end

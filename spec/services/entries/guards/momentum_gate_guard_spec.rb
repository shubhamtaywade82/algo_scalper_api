# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::MomentumGateGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: index_key },
        instrument: instrument
      }
    end
    let(:index_key) { 'NIFTY' }
    let(:instrument) { create(:instrument, :nifty_index) }
    let(:candle_series) { instance_double(CandleSeries, symbol: 'NIFTY', interval: '15', adx: 20.0) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: '15').and_return(candle_series)
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { momentum_gate: momentum_config })
    end

    context 'when momentum gate is disabled' do
      let(:momentum_config) { { enabled: false } }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when momentum gate is enabled' do
      let(:momentum_config) { { enabled: true, adx_threshold: 25 } }

      context 'and index_key is blank' do
        let(:index_key) { nil }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and instrument is not provided' do
        let(:instrument) { nil }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and candle series has insufficient data' do
        before do
          allow(candle_series).to receive(:candles).and_return([instance_double(Candle)])
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and BB breakout is detected' do
        let(:market_regime_detector) { instance_double(MarketRegimeDetector) }

        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:bollinger_band_breakout?).and_return(true)
          allow(candle_series).to receive(:adx).with(14).and_return(20.0)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and ADX is strong' do
        let(:market_regime_detector) { instance_double(MarketRegimeDetector) }

        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:bollinger_band_breakout?).and_return(false)
          allow(candle_series).to receive(:adx).with(14).and_return(30.0)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and neither BB breakout nor strong ADX' do
        let(:market_regime_detector) { instance_double(MarketRegimeDetector) }

        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:bollinger_band_breakout?).and_return(false)
          allow(candle_series).to receive(:adx).with(14).and_return(20.0)
        end

        it 'blocks entry with details' do
          result = described_class.call(context)
          expect(result).to include(blocked: /No momentum/)
          expect(result[:blocked]).to include('BB breakout=false')
          expect(result[:blocked]).to include('ADX=20.0')
          expect(result[:blocked]).to include('threshold: 25')
        end
      end

      context 'and an error occurs during check' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_raise(StandardError.new('test error'))
        end

        it 'allows entry (fails open)' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end
  end

  describe '.enabled?' do
    context 'when enabled is true in config' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { momentum_gate: { enabled: true } })
      end

      it 'returns true' do
        expect(described_class.enabled?).to be true
      end
    end

    context 'when enabled is false in config' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { momentum_gate: { enabled: false } })
      end

      it 'returns false' do
        expect(described_class.enabled?).to be false
      end
    end

    context 'when momentum_gate config is missing' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: {})
      end

      it 'returns false (default)' do
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe '.adx_threshold' do
    context 'when adx_threshold is configured' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { momentum_gate: { adx_threshold: 30 } })
      end

      it 'returns the configured value' do
        expect(described_class.adx_threshold).to eq(30.0)
      end
    end

    context 'when adx_threshold is not configured' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { momentum_gate: {} })
      end

      it 'returns the default threshold' do
        expect(described_class.adx_threshold).to eq(Entries::Guards::MomentumGateGuard::DEFAULT_ADX_THRESHOLD)
      end
    end
  end
end

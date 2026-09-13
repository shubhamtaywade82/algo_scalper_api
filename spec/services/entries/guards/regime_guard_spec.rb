# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::RegimeGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: index_key },
        instrument: instrument
      }
    end
    let(:index_key) { 'NIFTY' }
    let(:instrument) { create(:instrument, :nifty_index) }
    let(:candle_series) { instance_double(CandleSeries, symbol: 'NIFTY', interval: '15') }
    let(:market_regime_detector) { instance_double(MarketRegimeDetector) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: '15').and_return(candle_series)
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { regime_guard: regime_config })
    end

    context 'when regime guard is disabled' do
      let(:regime_config) { { enabled: false } }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when regime guard is enabled' do
      let(:regime_config) { { enabled: true, block_regimes: %w[CHOPPY], bypass_adx: 28 } }

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

      context 'and regime detection fails' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |_i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:detect).and_return(nil)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and detected regime is not in block list' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |_i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:detect).and_return({ regime: 'TRENDING', adx: 30.0 })
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and detected regime is in block list but ADX is above bypass threshold' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |_i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:detect).and_return({ regime: 'CHOPPY', adx: 30.0 })
          allow(candle_series).to receive(:adx).with(14).and_return(30.0)
        end

        it 'allows entry (ADX bypass)' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and detected regime is in block list and ADX is below bypass threshold' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |_i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_return(market_regime_detector)
          allow(market_regime_detector).to receive(:detect).and_return({ regime: 'CHOPPY', adx: 20.0 })
          allow(candle_series).to receive(:adx).with(14).and_return(20.0)
        end

        it 'blocks entry with regime details' do
          result = described_class.call(context)
          expect(result).to include(blocked: /Regime CHOPPY/)
          expect(result[:blocked]).to include('ADX=20.0')
        end
      end

      context 'and an error occurs during check' do
        before do
          allow(candle_series).to receive(:candles).and_return(Array.new(20) { |_i| instance_double(Candle) })
          allow(MarketRegimeDetector).to receive(:new).with(candle_series).and_raise(StandardError.new('test error'))
        end

        it 'allows entry (fails open)' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end
  end

  describe '.config' do
    context 'when regime_guard config exists' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { regime_guard: { enabled: true } })
      end

      it 'returns the config' do
        expect(described_class.config).to eq({ enabled: true })
      end
    end

    context 'when regime_guard config is missing' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: {})
      end

      it 'returns empty hash' do
        expect(described_class.config).to eq({})
      end
    end

    context 'when AlgoConfig.fetch raises an error' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('config error'))
      end

      it 'returns empty hash' do
        expect(described_class.config).to eq({})
      end
    end
  end

  describe '.detect_regime' do
    let(:series) { instance_double(CandleSeries) }
    let(:market_regime_detector) { instance_double(MarketRegimeDetector) }

    context 'when detection succeeds' do
      before do
        allow(MarketRegimeDetector).to receive(:new).with(series).and_return(market_regime_detector)
        allow(market_regime_detector).to receive(:detect).and_return({ regime: 'TRENDING', adx: 30.0 })
      end

      it 'returns regime data' do
        result = described_class.detect_regime(series)
        expect(result).to eq({ regime: 'TRENDING', adx: 30.0 })
      end
    end

    context 'when detection fails' do
      before do
        allow(MarketRegimeDetector).to receive(:new).with(series).and_raise(StandardError.new('detection error'))
      end

      it 'returns nil' do
        result = described_class.detect_regime(series)
        expect(result).to be_nil
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::VolatilityRegimeService do
  describe '.call' do
    context 'when VIX value is provided' do
      it 'returns high volatility regime for VIX > 20' do
        result = described_class.call(vix_value: 25.0)
        expect(result[:regime]).to eq(:high)
        expect(result[:vix_value]).to eq(25.0)
        expect(result[:regime_name]).to eq('High Volatility')
      end

      it 'returns medium volatility regime for VIX between 15-20' do
        result = described_class.call(vix_value: 17.5)
        expect(result[:regime]).to eq(:medium)
        expect(result[:vix_value]).to eq(17.5)
        expect(result[:regime_name]).to eq('Medium Volatility')
      end

      it 'returns low volatility regime for VIX < 15' do
        result = described_class.call(vix_value: 12.0)
        expect(result[:regime]).to eq(:low)
        expect(result[:vix_value]).to eq(12.0)
        expect(result[:regime_name]).to eq('Low Volatility')
      end

      it 'returns medium volatility for VIX exactly at threshold' do
        result = described_class.call(vix_value: 20.0)
        expect(result[:regime]).to eq(:medium)
      end

      it 'returns low volatility for VIX exactly at medium threshold' do
        result = described_class.call(vix_value: 15.0)
        expect(result[:regime]).to eq(:medium)
      end
    end

    context 'when VIX instrument exists' do
      let(:vix_instrument) { create(:instrument, symbol_name: 'INDIAVIX', security_id: '9999') }

      before do
        allow(Instrument).to receive(:find_by).with(symbol_name: 'INDIAVIX').and_return(vix_instrument)
        allow(Live::TickCache).to receive(:ltp).and_return(22.5)
      end

      it 'fetches VIX from instrument and returns high regime' do
        result = described_class.call
        expect(result[:regime]).to eq(:high)
        expect(result[:vix_value]).to eq(22.5)
      end

      it 'falls back to Redis tick cache if TickCache fails' do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return({ ltp: 18.5 })

        result = described_class.call
        expect(result[:regime]).to eq(:medium)
        expect(result[:vix_value]).to eq(18.5)
      end

      it 'falls back to API if cache fails' do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
        allow(vix_instrument).to receive(:ltp).and_return(14.0)

        result = described_class.call
        expect(result[:regime]).to eq(:low)
        expect(result[:vix_value]).to eq(14.0)
      end
    end

    context 'when VIX instrument not found' do
      let(:nifty_instrument) { create(:instrument, symbol_name: 'NIFTY', security_id: '9998') }
      let(:candle_series) { build(:candle_series, :with_candles) }
      let(:calculator) { instance_double(Indicators::Calculator, atr: 50.0) }

      before do
        allow(Instrument).to receive(:find_by).and_return(nil)
        allow(Instrument).to receive(:find_by).with(symbol_name: 'NIFTY').and_return(nifty_instrument)
        allow(nifty_instrument).to receive(:candle_series).with(interval: '5').and_return(candle_series)
        allow(Indicators::Calculator).to receive(:new).with(candle_series).and_return(calculator)
        allow(candle_series).to receive(:closes).and_return([100.0, 101.0, 102.0, 103.0, 104.0, 105.0])
      end

      it 'uses ATR proxy as fallback' do
        result = described_class.call
        expect(result[:regime]).to be_in([:low, :medium, :high])
        expect(result[:vix_value]).to be_a(Float)
      end

      it 'handles ATR proxy calculation errors gracefully' do
        allow(nifty_instrument).to receive(:candle_series).and_raise(StandardError, 'Test error')
        result = described_class.call
        expect(result[:regime]).to eq(:medium) # Default regime
        expect(result[:vix_value]).to be_nil
      end
    end

    context 'when all methods fail' do
      before do
        allow(Instrument).to receive(:find_by).and_return(nil)
        allow(Instrument).to receive(:find_by).with(symbol_name: 'NIFTY').and_return(nil)
      end

      it 'returns default medium regime' do
        result = described_class.call
        expect(result[:regime]).to eq(:medium)
        expect(result[:vix_value]).to be_nil
        expect(result[:regime_name]).to eq('Medium Volatility')
      end
    end

    context 'with custom VIX thresholds' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              vix_thresholds: {
                high: 25.0,
                medium: 18.0
              }
            }
          }
        })
      end

      it 'uses custom thresholds' do
        result = described_class.call(vix_value: 22.0)
        expect(result[:regime]).to eq(:medium) # Between 18 and 25
      end

      it 'classifies high volatility with custom threshold' do
        result = described_class.call(vix_value: 26.0)
        expect(result[:regime]).to eq(:high)
      end
    end

    context 'error handling' do
      it 'handles exceptions gracefully' do
        allow(Instrument).to receive(:find_by).and_raise(StandardError, 'Database error')
        result = described_class.call
        expect(result[:regime]).to eq(:medium)
        expect(result[:vix_value]).to be_nil
      end
    end
  end
end

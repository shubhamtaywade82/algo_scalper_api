# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine confidence score enhancements' do
  def make_series
    instance_double('CandleSeries', candles: [double(close: 100.0)] * 30)
  end

  describe '.macd_confidence_factor' do
    context 'bullish direction with positive MACD histogram' do
      it 'returns 0.10' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: 0.5 }, direction: :bullish }))
        expect(Signal::Engine.send(:macd_confidence_factor, :bullish, series)).to eq(0.10)
      end
    end

    context 'bearish direction with negative MACD histogram' do
      it 'returns 0.10' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: -0.3 }, direction: :bearish }))
        expect(Signal::Engine.send(:macd_confidence_factor, :bearish, series)).to eq(0.10)
      end
    end

    context 'direction mismatch (bearish direction but positive histogram)' do
      it 'returns 0.0' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: 0.5 }, direction: :bullish }))
        expect(Signal::Engine.send(:macd_confidence_factor, :bearish, series)).to eq(0.0)
      end
    end

    context 'when MacdIndicator raises' do
      it 'returns 0.0 safely' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new).and_raise(StandardError)
        expect(Signal::Engine.send(:macd_confidence_factor, :bullish, series)).to eq(0.0)
      end
    end
  end

  describe '.smc_bias_confidence_factor' do
    let(:index_cfg) { double('IndexConfig', key: 'NIFTY') }

    context 'SMC bias fully aligns with signal direction' do
      it 'returns 0.20' do
        allow(Signal::Engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:bullish)
        expect(Signal::Engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.20)
      end
    end

    context 'SMC bias is neutral' do
      it 'returns 0.05' do
        allow(Signal::Engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:neutral)
        expect(Signal::Engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.05)
      end
    end

    context 'SMC bias misaligned' do
      it 'returns 0.0' do
        allow(Signal::Engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:bearish)
        expect(Signal::Engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.0)
      end
    end
  end
end

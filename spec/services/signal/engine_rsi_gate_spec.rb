# frozen_string_literal: true

require 'rails_helper'

# Focused spec for the RSI anti-chase gate added to Signal::Engine#comprehensive_validation.
# Tests the gate in isolation by stubbing AlgoConfig and the RSI indicator.
RSpec.describe 'Signal::Engine RSI anti-chase gate' do
  let(:engine) { Signal::Engine }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      signals: {
        validation_modes: {
          balanced: {
            require_rsi_check: true,
            rsi_overbought_block: 78,
            rsi_oversold_block: 22
          }
        }
      }
    })
  end

  def make_series(rsi_value)
    series = instance_double('CandleSeries', candles: [double(close: 100.0)] * 20)
    indicator = instance_double('Indicators::RsiIndicator', rsi_value_at: rsi_value)
    allow(Indicators::RsiIndicator).to receive(:new).with(series: series).and_return(indicator)
    series
  end

  describe 'CE entry (bullish direction)' do
    context 'RSI at 82 (overbought — chasing a top)' do
      it 'blocks the entry' do
        result = engine.send(:validate_rsi_gate, :bullish, make_series(82), { require_rsi_check: true, rsi_overbought_block: 78 })
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('RSI overbought')
      end
    end

    context 'RSI at 60 (normal bullish momentum zone)' do
      it 'passes' do
        result = engine.send(:validate_rsi_gate, :bullish, make_series(60), { require_rsi_check: true, rsi_overbought_block: 78 })
        expect(result[:valid]).to be true
      end
    end
  end

  describe 'PE entry (bearish direction)' do
    context 'RSI at 15 (oversold — chasing a bottom)' do
      it 'blocks the entry' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(15), { require_rsi_check: true, rsi_oversold_block: 22 })
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('RSI oversold')
      end
    end

    context 'RSI at 38 (normal bearish momentum zone)' do
      it 'passes' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(38), { require_rsi_check: true, rsi_oversold_block: 22 })
        expect(result[:valid]).to be true
      end
    end

    context 'require_rsi_check: false' do
      it 'always passes regardless of RSI' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(10), { require_rsi_check: false })
        expect(result[:valid]).to be true
      end
    end
  end
end

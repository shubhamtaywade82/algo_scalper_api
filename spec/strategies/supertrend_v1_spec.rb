# frozen_string_literal: true

require 'rails_helper'
load Rails.root.join('strategies/supertrend_v1/strategy.rb').to_s

RSpec.describe SupertrendV1 do
  subject(:strategy) { described_class.new(params: { supertrend_period: 10, supertrend_multiplier: 2.0, adx_min: 20.0 }) }

  let(:context) { instance_double(Strategies::StrategyContext) }
  let(:candles_1m) { instance_double(CandleSeries) }
  let(:candles_5m) { instance_double(CandleSeries) }

  let(:supertrend_bullish) { { line: [100.0, 100.0], trend: :bullish, last_value: 100.0 } }
  let(:supertrend_bearish) { { line: [200.0, 200.0], trend: :bearish, last_value: 200.0 } }

  before do
    candles_callable = double('CandleCallable') # rubocop:disable RSpec/VerifiedDoubles
    allow(candles_callable).to receive(:call).with('1m').and_return(candles_1m)
    allow(candles_callable).to receive(:call).with('5m').and_return(candles_5m)
    allow(context).to receive(:candles).and_return(candles_callable)

    candle_obj = double('Candle', close: 150.0) # rubocop:disable RSpec/VerifiedDoubles
    allow(candles_1m).to receive(:candles).and_return([candle_obj, candle_obj])
    allow(candles_5m).to receive(:candles).and_return([candle_obj, candle_obj])
  end

  context 'when 1m and 5m trends align bullish and ADX is sufficient' do
    it 'returns BuyCall signal' do
      st_service_1m = instance_double(Indicators::Supertrend, call: supertrend_bullish)
      st_service_5m = instance_double(Indicators::Supertrend, call: supertrend_bullish)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_1m, period: 10, base_multiplier: 2.0).and_return(st_service_1m)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_5m, period: 10, base_multiplier: 2.0).and_return(st_service_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(25.0)

      signal = strategy.call(context)
      expect(signal).to be_a(Signals::BuyCall)
      expect(signal.reason).to include('mtf_supertrend_bullish_adx_25.0')
    end
  end

  context 'when 1m and 5m trends align bearish and ADX is sufficient' do
    it 'returns BuyPut signal' do
      st_service_1m = instance_double(Indicators::Supertrend, call: supertrend_bearish)
      st_service_5m = instance_double(Indicators::Supertrend, call: supertrend_bearish)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_1m, period: 10, base_multiplier: 2.0).and_return(st_service_1m)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_5m, period: 10, base_multiplier: 2.0).and_return(st_service_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(22.0)

      signal = strategy.call(context)
      expect(signal).to be_a(Signals::BuyPut)
      expect(signal.reason).to include('mtf_supertrend_bearish_adx_22.0')
    end
  end

  context 'when 1m and 5m trends mismatch' do
    it 'returns Hold signal with mtf_trend_mismatch reason' do
      st_service_1m = instance_double(Indicators::Supertrend, call: supertrend_bullish)
      st_service_5m = instance_double(Indicators::Supertrend, call: supertrend_bearish)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_1m, period: 10, base_multiplier: 2.0).and_return(st_service_1m)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_5m, period: 10, base_multiplier: 2.0).and_return(st_service_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(25.0)

      signal = strategy.call(context)
      expect(signal).to be_a(Signals::Hold)
      expect(signal.reason).to include('mtf_trend_mismatch')
    end
  end

  context 'when ADX is below minimum' do
    it 'returns Hold signal with adx_below_min reason' do
      st_service_1m = instance_double(Indicators::Supertrend, call: supertrend_bullish)
      st_service_5m = instance_double(Indicators::Supertrend, call: supertrend_bullish)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_1m, period: 10, base_multiplier: 2.0).and_return(st_service_1m)
      allow(Indicators::Supertrend).to receive(:new).with(series: candles_5m, period: 10, base_multiplier: 2.0).and_return(st_service_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(15.0)

      signal = strategy.call(context)
      expect(signal).to be_a(Signals::Hold)
      expect(signal.reason).to include('adx_below_min(15.0)')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::Strategies::SupertrendAdx do
  subject(:strategy) { described_class.new(index_key: 'NIFTY', security_id: '13') }

  let(:candles_1m) { instance_double(CandleSeries) }
  let(:candles_5m) { instance_double(CandleSeries) }

  let(:st_bullish) { { line: [100.0, 100.0], trend: :bullish } }
  let(:st_bearish) { { line: [200.0, 200.0], trend: :bearish } }

  before do
    segment_scope = double('SegmentIndexScope') # rubocop:disable RSpec/VerifiedDoubles
    allow(Instrument).to receive(:segment_index).and_return(segment_scope)
    allow(segment_scope).to receive(:find_by).and_return(nil)

    allow(Candles::Repository).to receive(:series).with(hash_including(timeframe: '1m')).and_return(candles_1m)
    allow(Candles::Repository).to receive(:series).with(hash_including(timeframe: '5m')).and_return(candles_5m)

    candle_obj = double('Candle', close: 150.0) # rubocop:disable RSpec/VerifiedDoubles
    allow(candles_1m).to receive(:candles).and_return([candle_obj, candle_obj])
    allow(candles_5m).to receive(:candles).and_return([candle_obj, candle_obj])
    allow(OptionsBuying::StateStore).to receive(:radar_strikes).and_return([])
  end

  context 'when 1m and 5m Supertrend align bullish and ADX >= 20' do
    it 'returns bullish signal hash' do
      st_1m = instance_double(Indicators::Supertrend, call: st_bullish)
      st_5m = instance_double(Indicators::Supertrend, call: st_bullish)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_1m)).and_return(st_1m)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_5m)).and_return(st_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(24.5)

      result = strategy.check_entry({ spot_ltp: 24_000.0 })
      expect(result).not_to be_nil
      expect(result[:direction]).to eq(:bullish)
      expect(result[:metrics][:adx]).to eq(24.5)
    end
  end

  context 'when 1m and 5m Supertrend align bearish and ADX >= 20' do
    it 'returns bearish signal hash' do
      st_1m = instance_double(Indicators::Supertrend, call: st_bearish)
      st_5m = instance_double(Indicators::Supertrend, call: st_bearish)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_1m)).and_return(st_1m)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_5m)).and_return(st_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(21.0)

      result = strategy.check_entry({ spot_ltp: 24_000.0 })
      expect(result).not_to be_nil
      expect(result[:direction]).to eq(:bearish)
    end
  end

  context 'when 1m and 5m trends mismatch' do
    it 'returns nil' do
      st_1m = instance_double(Indicators::Supertrend, call: st_bullish)
      st_5m = instance_double(Indicators::Supertrend, call: st_bearish)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_1m)).and_return(st_1m)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_5m)).and_return(st_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(25.0)

      result = strategy.check_entry({ spot_ltp: 24_000.0 })
      expect(result).to be_nil
    end
  end

  context 'when ADX is below threshold' do
    it 'returns nil' do
      st_1m = instance_double(Indicators::Supertrend, call: st_bullish)
      st_5m = instance_double(Indicators::Supertrend, call: st_bullish)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_1m)).and_return(st_1m)
      allow(Indicators::Supertrend).to receive(:new).with(hash_including(series: candles_5m)).and_return(st_5m)

      allow(candles_1m).to receive(:adx).with(14).and_return(18.0)

      result = strategy.check_entry({ spot_ltp: 24_000.0 })
      expect(result).to be_nil
    end
  end
end

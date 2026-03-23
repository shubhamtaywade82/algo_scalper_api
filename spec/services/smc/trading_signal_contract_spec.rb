# frozen_string_literal: true

require 'rails_helper'
require 'json_schemer'

RSpec.describe Smc::TradingSignalContract do
  let(:series_5m) { build(:candle_series, :five_minute, :with_candles) }
  let(:series_15m) { build(:candle_series, :fifteen_minute, :with_candles) }
  let(:schema) { JSONSchemer.schema(Rails.root.join('schemas/smc_trading_signal.json')) }

  describe '.build' do
    it 'produces a schema-valid payload' do
      result = described_class.build(
        series_5m: series_5m,
        series_15m: series_15m,
        symbol: 'NIFTY',
        ltp: series_5m.candles.last.close
      )

      expect(schema.valid?(result[:payload])).to be(true), -> { schema.validate(result[:payload]).to_a.inspect }
    end
  end

  describe '.publish!' do
    it 'persists a signal event' do
      expect do
        described_class.publish!(
          series_5m: series_5m,
          series_15m: series_15m,
          symbol: 'NIFTY',
          ltp: series_5m.candles.last.close
        )
      end.to change(SmcEvent, :count).by(1)

      row = SmcEvent.order(:id).last
      expect(row.event_type).to eq('signal')
      expect(row.stream).to eq('NIFTY-5m')
    end
  end
end

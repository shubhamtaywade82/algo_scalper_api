# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::SignalSnapshotBuilder do
  describe '.build' do
    it 'creates a Research::Signal snapshot with normalized symbol/direction' do
      signal = described_class.build(
        underlying_symbol: 'nifty',
        signal_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
        direction: 'bullish',
        spot_price: 24_982
      )

      expect(signal).to be_persisted
      expect(signal.underlying_symbol).to eq('NIFTY')
      expect(signal.direction).to eq('bullish')
      expect(signal.source).to eq('manual')
    end
  end

  describe '.from_trading_signal' do
    let(:trading_signal) do
      TradingSignal.create!(
        index_key: 'NIFTY',
        direction: 'avoid',
        timeframe: '5m',
        supertrend_value: 24_900,
        adx_value: 22,
        candle_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
        signal_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
        metadata: { 'spot_price' => 24_982 }
      )
    end

    it 'maps avoid -> no_trade and pulls spot_price from metadata' do
      signal = described_class.from_trading_signal(trading_signal)

      expect(signal.direction).to eq('no_trade')
      expect(signal.spot_price.to_f).to eq(24_982.0)
      expect(signal.source).to eq('trading_signal')
      expect(signal.source_id).to eq(trading_signal.id)
      expect(signal.source_type).to eq('TradingSignal')
    end

    it 'raises when spot_price cannot be resolved' do
      trading_signal.update_columns(metadata: {}) # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.from_trading_signal(trading_signal) }.to raise_error(ArgumentError)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::BiasEngine do
  describe '#decision' do
    it 'does not instantiate AVRZ when HTF bias is invalid' do
      instrument = instance_double(Instrument)
      allow(instrument).to receive_messages(candles: build(:candle_series, :one_hour), ltp: nil, latest_ltp: 25_000.0)

      htf_ctx = instance_double(Smc::Context)
      mtf_ctx = instance_double(Smc::Context)
      ltf_ctx = instance_double(Smc::Context)

      htf_pd = instance_double(Smc::Detectors::PremiumDiscount, premium?: false, discount?: false)
      allow(htf_ctx).to receive(:pd).and_return(htf_pd)

      allow(Smc::Context).to receive(:new).and_return(htf_ctx, mtf_ctx, ltf_ctx)

      expect(Avrz::Detector).not_to receive(:new)
      expect(described_class.new(instrument).decision).to eq(:no_trade)
    end

    it 'uses AVRZ only inside LTF entry' do
      htf_series = build(:candle_series, :one_hour, :with_candles)
      mtf_series = build(:candle_series, :fifteen_minute, :with_candles)
      ltf_series = build(:candle_series, :five_minute, :with_candles)

      instrument = instance_double(Instrument)
      allow(instrument).to receive(:candles).with(interval: '60').and_return(htf_series)
      allow(instrument).to receive(:candles).with(interval: '15').and_return(mtf_series)
      allow(instrument).to receive(:candles).with(interval: '5').and_return(ltf_series)
      allow(instrument).to receive_messages(ltp: nil, latest_ltp: 25_000.0, symbol_name: 'NIFTY')

      htf_pd = instance_double(Smc::Detectors::PremiumDiscount, premium?: false, discount?: true)
      htf_structure = instance_double(Smc::Detectors::Structure, trend: :bullish)
      htf_ctx = instance_double(Smc::Context, pd: htf_pd, structure: htf_structure)

      mtf_structure = instance_double(Smc::Detectors::Structure, trend: :bullish, choch?: false)
      mtf_ctx = instance_double(Smc::Context, structure: mtf_structure)

      ltf_liq = instance_double(Smc::Detectors::Liquidity, sell_side_taken?: true, buy_side_taken?: false,
                                                           sweep_direction: :sell_side)
      ltf_structure = instance_double(Smc::Detectors::Structure, choch?: true)
      ltf_ctx = instance_double(Smc::Context, liquidity: ltf_liq, structure: ltf_structure)

      allow(Smc::Context).to receive(:new).and_return(htf_ctx, mtf_ctx, ltf_ctx)

      avrz = instance_double(Avrz::Detector, rejection?: true)
      expect(Avrz::Detector).to receive(:new).with(ltf_series).and_return(avrz)

      # Disable Telegram notifications in test
      allow(AlgoConfig).to receive(:fetch).and_return({ telegram: { enabled: false } })

      expect(described_class.new(instrument).decision).to eq(:call)
    end
  end
end

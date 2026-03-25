# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::BiasEngine do
  describe '#decision' do
    def build_instrument_for_bullish_call
      htf_series = build(:candle_series, :one_hour, :with_candles)
      mtf_series = build(:candle_series, :fifteen_minute, :with_candles)
      ltf_series = build(:candle_series, :five_minute, :with_candles)

      instrument = instance_double(Instrument)
      allow(instrument).to receive(:candles).with(interval: '60').and_return(htf_series)
      allow(instrument).to receive(:candles).with(interval: '15').and_return(mtf_series)
      allow(instrument).to receive(:candles).with(interval: '5').and_return(ltf_series)
      allow(instrument).to receive_messages(ltp: nil, latest_ltp: 25_000.0, symbol_name: 'NIFTY', id: 1)
      instrument
    end

    def stub_aligned_smc_contexts
      htf_pd = instance_double(Smc::Detectors::PremiumDiscount, premium?: false, discount?: true)
      htf_structure = instance_double(Smc::Detectors::Structure, trend: :bullish)
      htf_ctx = instance_double(Smc::Context, pd: htf_pd, structure: htf_structure)

      mtf_structure = instance_double(Smc::Detectors::Structure, trend: :bullish, choch?: false)
      mtf_ctx = instance_double(Smc::Context, structure: mtf_structure)

      ltf_liq = instance_double(Smc::Detectors::Liquidity, sell_side_taken?: true, buy_side_taken?: false,
                                                           sweep_direction: :sell_side)
      ltf_structure = instance_double(Smc::Detectors::Structure, choch?: true, trend: :bullish)
      ltf_ctx = instance_double(Smc::Context, liquidity: ltf_liq, structure: ltf_structure, phase: :neutral)

      allow(Smc::Context).to receive(:new).and_return(htf_ctx, mtf_ctx, ltf_ctx)
      allow(htf_ctx).to receive(:to_h).and_return({})
      allow(mtf_ctx).to receive(:to_h).and_return({})
      allow(ltf_ctx).to receive(:to_h).and_return({})
    end

    it 'does not instantiate AVRZ when HTF bias is invalid' do
      instrument = instance_double(Instrument)
      allow(instrument).to receive_messages(candles: build(:candle_series, :one_hour), ltp: nil, latest_ltp: 25_000.0)

      htf_ctx = instance_double(Smc::Context)
      mtf_ctx = instance_double(Smc::Context)
      ltf_ctx = instance_double(Smc::Context)

      htf_pd = instance_double(Smc::Detectors::PremiumDiscount, premium?: false, discount?: false)
      allow(htf_ctx).to receive(:pd).and_return(htf_pd)

      allow(Smc::Context).to receive(:new).and_return(htf_ctx, mtf_ctx, ltf_ctx)
      allow(Avrz::Detector).to receive(:new)

      expect(described_class.new(instrument).decision).to eq(:no_trade)
      expect(Avrz::Detector).not_to have_received(:new)
    end

    it 'returns :call when HTF discount, MTF aligned, and LTF sweep with bullish trend' do
      instrument = build_instrument_for_bullish_call
      stub_aligned_smc_contexts
      allow(Avrz::Detector).to receive(:new)

      allow(AlgoConfig).to receive(:fetch).and_return({ telegram: { enabled: false } })
      allow(Notifications::Telegram::SendSmcAlertJob).to receive(:perform_later)

      expect(described_class.new(instrument).decision).to eq(:call)
      expect(Avrz::Detector).not_to have_received(:new)
    end
  end
end

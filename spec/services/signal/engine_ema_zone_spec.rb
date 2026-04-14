# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine EMA tie-break and SMC zone filter' do
  def make_series(count: 30)
    instance_double('CandleSeries', candles: [double(close: 100.0)] * count)
  end

  describe '.check_ema_direction_alignment' do
    context 'Supertrend and EMA agree (both bullish)' do
      it 'returns aligned: true, adx_override_needed: false' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bullish }))
        result = Signal::Engine.send(:check_ema_direction_alignment, :bullish, series, 20.0)
        expect(result[:aligned]).to be true
        expect(result[:adx_override_needed]).to be false
      end
    end

    context 'Supertrend bullish but EMA bearish, ADX 22 (below override threshold)' do
      it 'returns adx_override_needed: true' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bearish }))
        result = Signal::Engine.send(:check_ema_direction_alignment, :bullish, series, 22.0)
        expect(result[:adx_override_needed]).to be true
      end
    end

    context 'Supertrend bullish but EMA bearish, ADX 28 (above 25 threshold)' do
      it 'returns aligned: true (strong momentum overrides EMA disagreement)' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bearish }))
        result = Signal::Engine.send(:check_ema_direction_alignment, :bullish, series, 28.0)
        expect(result[:aligned]).to be true
      end
    end
  end

  describe '.smc_zone_allows_entry?' do
    let(:index_cfg) { double('IndexConfig') }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        signals: { smc: { zone_filter_adx_override: 30 } }
      })
    end

    context 'CE entry in discount zone (ideal)' do
      it 'returns true' do
        allow(Signal::Engine).to receive(:get_smc_zone).with(index_cfg).and_return(:discount)
        expect(Signal::Engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 20.0)).to be true
      end
    end

    context 'CE entry in premium zone, ADX 22 (below override threshold of 30)' do
      it 'returns false (chasing top in premium zone)' do
        allow(Signal::Engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(Signal::Engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 22.0)).to be false
      end
    end

    context 'CE entry in premium zone, ADX 32 (strong momentum override)' do
      it 'returns true (momentum overrides zone restriction)' do
        allow(Signal::Engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(Signal::Engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 32.0)).to be true
      end
    end

    context 'PE entry in premium zone (ideal for puts)' do
      it 'returns true' do
        allow(Signal::Engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(Signal::Engine.send(:smc_zone_allows_entry?, :bearish, index_cfg, 20.0)).to be true
      end
    end
  end
end

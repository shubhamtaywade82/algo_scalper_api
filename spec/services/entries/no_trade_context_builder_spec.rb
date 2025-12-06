# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::NoTradeContextBuilder do
  let(:index_key) { 'NIFTY' }
  let(:bars_1m) { build_list(:candle, 20, timestamp: ->(i) { i.minutes.ago }) }
  let(:bars_5m) { build_list(:candle, 20, timestamp: ->(i) { (i * 5).minutes.ago }) }
  let(:option_chain_data) do
    {
      ce: {
        '25000' => { 'oi' => 1000, 'iv' => 15.0, 'bid' => 100.0, 'ask' => 101.0, 'ltp' => 100.5 }
      },
      pe: {
        '25000' => { 'oi' => 2000, 'iv' => 14.0, 'bid' => 90.0, 'ask' => 91.0, 'ltp' => 90.5 }
      }
    }
  end

  describe '.build' do
    before do
      # Mock ADX calculation
      allow(described_class).to receive(:calculate_adx_data).and_return(
        adx: 20.0,
        plus_di: 25.0,
        minus_di: 10.0
      )

      # Mock structure detection
      allow(Entries::StructureDetector).to receive(:bos?).and_return(true)
      allow(Entries::StructureDetector).to receive(:inside_opposite_ob?).and_return(false)
      allow(Entries::StructureDetector).to receive(:inside_fvg?).and_return(false)

      # Mock VWAP utilities
      allow(Entries::VWAPUtils).to receive(:near_vwap?).and_return(false)
      allow(Entries::VWAPUtils).to receive(:trapped_between_vwap_avwap?).and_return(false)
      allow(Entries::VWAPUtils).to receive(:vwap_chop?).and_return(false)

      # Mock range utilities
      allow(Entries::RangeUtils).to receive(:range_pct).and_return(0.5)

      # Mock ATR utilities
      allow(Entries::ATRUtils).to receive(:atr_downtrend?).and_return(false)

      # Mock candle utilities
      allow(Entries::CandleUtils).to receive(:avg_wick_ratio).and_return(1.0)

      # Mock option chain wrapper
      chain_wrapper = instance_double(Entries::OptionChainWrapper)
      allow(chain_wrapper).to receive(:ce_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:pe_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:atm_iv).and_return(15.0)
      allow(chain_wrapper).to receive(:iv_falling?).and_return(false)
      allow(chain_wrapper).to receive(:spread_wide?).and_return(false)
      allow(Entries::OptionChainWrapper).to receive(:new).and_return(chain_wrapper)
    end

    it 'builds context with all required fields' do
      ctx = described_class.build(
        index: index_key,
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )

      expect(ctx.adx_5m).to eq(20.0)
      expect(ctx.plus_di_5m).to eq(25.0)
      expect(ctx.minus_di_5m).to eq(10.0)
      expect(ctx.bos_present).to be true
      expect(ctx.in_opposite_ob).to be false
      expect(ctx.inside_fvg).to be false
      expect(ctx.index_key).to eq('NIFTY')
      expect(ctx.near_vwap).to be false
      expect(ctx.trapped_between_vwap).to be false
      expect(ctx.vwap_chop).to be false
      expect(ctx.range_10m_pct).to eq(0.5)
      expect(ctx.atr_downtrend).to be false
      expect(ctx.ce_oi_up).to be false
      expect(ctx.pe_oi_up).to be false
      expect(ctx.iv).to eq(15.0)
      expect(ctx.iv_falling).to be false
      expect(ctx.spread_wide).to be false
      expect(ctx.spread_wide_soft).to be false
      expect(ctx.avg_wick_ratio).to eq(1.0)
      expect(ctx.time).to eq('10:30')
    end

    it 'sets correct IV threshold for NIFTY' do
      ctx = described_class.build(
        index: 'NIFTY',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )

      expect(ctx.min_iv_threshold).to eq(10)
    end

    it 'sets correct IV threshold for BANKNIFTY' do
      ctx = described_class.build(
        index: 'BANKNIFTY',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )

      expect(ctx.min_iv_threshold).to eq(13)
    end

    it 'sets correct IV threshold for SENSEX' do
      ctx = described_class.build(
        index: 'SENSEX',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )

      expect(ctx.min_iv_threshold).to eq(11)
    end

    it 'calls vwap_chop? with NIFTY-specific parameters' do
      expect(Entries::VWAPUtils).to receive(:vwap_chop?).with(
        bars_1m,
        threshold_pct: 0.08,
        min_candles: 3
      ).and_return(false)

      described_class.build(
        index: 'NIFTY',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )
    end

    it 'calls vwap_chop? with SENSEX-specific parameters' do
      expect(Entries::VWAPUtils).to receive(:vwap_chop?).with(
        bars_1m,
        threshold_pct: 0.06,
        min_candles: 2
      ).and_return(false)

      described_class.build(
        index: 'SENSEX',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )
    end

    it 'calls atr_downtrend? with NIFTY-specific min_bars' do
      expect(Entries::ATRUtils).to receive(:atr_downtrend?).with(
        bars_1m,
        min_bars: 5
      ).and_return(false)

      described_class.build(
        index: 'NIFTY',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )
    end

    it 'calls atr_downtrend? with SENSEX-specific min_bars' do
      expect(Entries::ATRUtils).to receive(:atr_downtrend?).with(
        bars_1m,
        min_bars: 3
      ).and_return(false)

      described_class.build(
        index: 'SENSEX',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )
    end

    it 'calls spread_wide? with hard_reject parameter' do
      chain_wrapper = instance_double(Entries::OptionChainWrapper)
      allow(chain_wrapper).to receive(:ce_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:pe_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:atm_iv).and_return(15.0)
      allow(chain_wrapper).to receive(:iv_falling?).and_return(false)
      allow(chain_wrapper).to receive(:spread_wide?).with(hard_reject: true).and_return(false)
      allow(chain_wrapper).to receive(:spread_wide?).with(hard_reject: false).and_return(false)
      allow(Entries::OptionChainWrapper).to receive(:new).and_return(chain_wrapper)

      described_class.build(
        index: 'NIFTY',
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '10:30'
      )
    end

    it 'handles Time object for time parameter' do
      time_obj = Time.current

      ctx = described_class.build(
        index: index_key,
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: time_obj
      )

      expect(ctx.time).to eq(time_obj.strftime('%H:%M'))
    end

    it 'handles string time parameter' do
      ctx = described_class.build(
        index: index_key,
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '14:30'
      )

      expect(ctx.time).to eq('14:30')
    end

    it 'provides time_between helper method' do
      ctx = described_class.build(
        index: index_key,
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: option_chain_data,
        time: '12:00'
      )

      result = ctx.time_between.call('11:20', '13:30')
      expect(result).to be true

      result = ctx.time_between.call('09:15', '09:18')
      expect(result).to be false
    end

    it 'handles OptionChainWrapper instance' do
      chain_wrapper = instance_double(Entries::OptionChainWrapper)
      allow(chain_wrapper).to receive(:ce_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:pe_oi_rising?).and_return(false)
      allow(chain_wrapper).to receive(:atm_iv).and_return(15.0)
      allow(chain_wrapper).to receive(:iv_falling?).and_return(false)
      allow(chain_wrapper).to receive(:spread_wide?).with(hard_reject: true).and_return(false)
      allow(chain_wrapper).to receive(:spread_wide?).with(hard_reject: false).and_return(false)

      ctx = described_class.build(
        index: index_key,
        bars_1m: bars_1m,
        bars_5m: bars_5m,
        option_chain: chain_wrapper,
        time: '10:30'
      )

      expect(ctx.iv).to eq(15.0)
    end

    context 'when ADX calculation fails' do
      before do
        allow(described_class).to receive(:calculate_adx_data).and_raise(StandardError.new('ADX error'))
        allow_any_instance_of(CandleSeries).to receive(:adx).and_return(18.0)
      end

      it 'falls back to simple ADX value' do
        ctx = described_class.build(
          index: index_key,
          bars_1m: bars_1m,
          bars_5m: bars_5m,
          option_chain: option_chain_data,
          time: '10:30'
        )

        expect(ctx.adx_5m).to eq(18.0)
        expect(ctx.plus_di_5m).to eq(0)
        expect(ctx.minus_di_5m).to eq(0)
      end
    end

    context 'when bars_5m has insufficient data' do
      let(:insufficient_bars) { build_list(:candle, 5) }

      it 'returns zero ADX values' do
        ctx = described_class.build(
          index: index_key,
          bars_1m: bars_1m,
          bars_5m: insufficient_bars,
          option_chain: option_chain_data,
          time: '10:30'
        )

        expect(ctx.adx_5m).to eq(0)
        expect(ctx.plus_di_5m).to eq(0)
        expect(ctx.minus_di_5m).to eq(0)
      end
    end
  end
end

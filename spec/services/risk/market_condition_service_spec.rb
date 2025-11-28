# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::MarketConditionService do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:instrument) { instance_double(Instrument) }
  let(:primary_series) { build(:candle_series, :with_candles) }
  let(:calculator) { instance_double(Indicators::Calculator, adx: 25.0) }
  let(:trend_result) { { trend_score: 15.0, breakdown: { pa: 5, ind: 5, mtf: 5, vol: 0 } } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [index_cfg]
    })
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(instrument)
    allow(instrument).to receive(:candle_series).with(interval: '1').and_return(primary_series)
    allow(Indicators::Calculator).to receive(:new).with(primary_series).and_return(calculator)
  end

  describe '.call' do
    context 'with bullish conditions' do
      before do
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 16.0 })
        )
      end

      it 'returns bullish condition when trend_score >= 14 and ADX >= 20' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:bullish)
        expect(result[:condition_name]).to eq('Bullish')
        expect(result[:trend_score]).to eq(16.0)
        expect(result[:adx_value]).to eq(25.0)
      end
    end

    context 'with bearish conditions' do
      before do
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 6.0 })
        )
      end

      it 'returns bearish condition when trend_score <= 7 and ADX >= 20' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:bearish)
        expect(result[:condition_name]).to eq('Bearish')
        expect(result[:trend_score]).to eq(6.0)
        expect(result[:adx_value]).to eq(25.0)
      end
    end

    context 'with neutral conditions' do
      before do
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 10.0 })
        )
      end

      it 'returns neutral when trend_score is between 7 and 14' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:condition_name]).to eq('Neutral')
      end

      it 'returns neutral when ADX < 20 even with strong trend score' do
        allow(calculator).to receive(:adx).and_return(15.0)
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 18.0 })
        )

        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
      end
    end

    context 'when index config not found' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ indices: [] })
      end

      it 'returns default neutral result' do
        result = described_class.call(index_key: 'UNKNOWN')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:trend_score]).to be_nil
        expect(result[:adx_value]).to be_nil
      end
    end

    context 'when instrument not found' do
      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)
      end

      it 'returns default neutral result' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:trend_score]).to be_nil
      end
    end

    context 'when trend score calculation fails' do
      before do
        allow(Signal::TrendScorer).to receive(:new).and_raise(StandardError, 'Trend score error')
      end

      it 'returns neutral condition' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:trend_score]).to be_nil
      end
    end

    context 'when ADX calculation fails' do
      before do
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 16.0 })
        )
        allow(instrument).to receive(:candle_series).and_raise(StandardError, 'ADX error')
      end

      it 'returns neutral condition' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:adx_value]).to be_nil
      end
    end

    context 'with different index keys' do
      let(:banknifty_cfg) { { key: 'BANKNIFTY', segment: 'IDX_I', sid: '25' } }

      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          indices: [index_cfg, banknifty_cfg]
        })
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(banknifty_cfg).and_return(instrument)
        allow(Signal::TrendScorer).to receive(:new).and_return(
          instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 15.0 })
        )
      end

      it 'works with BANKNIFTY' do
        result = described_class.call(index_key: 'BANKNIFTY')
        expect(result[:condition]).to eq(:bullish)
      end

      it 'works with SENSEX' do
        sensex_cfg = { key: 'SENSEX', segment: 'IDX_I', sid: '51' }
        allow(AlgoConfig).to receive(:fetch).and_return({ indices: [sensex_cfg] })
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(sensex_cfg).and_return(instrument)

        result = described_class.call(index_key: 'SENSEX')
        expect(result[:condition]).to eq(:bullish)
      end
    end

    context 'error handling' do
      it 'handles exceptions gracefully' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:condition]).to eq(:neutral)
        expect(result[:trend_score]).to be_nil
      end
    end
  end
end

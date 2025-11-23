# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::IndexSelector do
  let(:config) { {} }
  let(:selector) { described_class.new(config: config) }

  describe '#initialize' do
    it 'initializes with default min_trend_score' do
      expect(selector.min_trend_score).to eq(15.0)
    end

    it 'accepts custom min_trend_score' do
      custom_selector = described_class.new(config: { min_trend_score: 20.0 })
      expect(custom_selector.min_trend_score).to eq(20.0)
    end
  end

  describe '#select_best_index' do
    let(:indices_config) do
      [
        { key: :NIFTY, segment: 'IDX_I', sid: '13' },
        { key: :BANKNIFTY, segment: 'IDX_I', sid: '25' },
        { key: :SENSEX, segment: 'IDX_I', sid: '51' }
      ]
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({ indices: indices_config })
    end

    context 'when no indices configured' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ indices: [] })
      end

      it 'returns nil' do
        expect(selector.select_best_index).to be_nil
      end
    end

    context 'when indices are configured' do
      let(:nifty_instrument) { instance_double(Instrument, symbol_name: 'NIFTY') }
      let(:banknifty_instrument) { instance_double(Instrument, symbol_name: 'BANKNIFTY') }
      let(:sensex_instrument) { instance_double(Instrument, symbol_name: 'SENSEX') }

      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_key: :NIFTY).and_return(nifty_instrument)
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_key: :BANKNIFTY).and_return(banknifty_instrument)
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_key: :SENSEX).and_return(sensex_instrument)
      end

      context 'when all indices score below minimum' do
        before do
          allow(Signal::TrendScorer).to receive(:new).and_return(scorer)
          allow(scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 10.0, breakdown: { pa: 2, ind: 3, mtf: 3, vol: 2 } }
          )
        end

        let(:scorer) { instance_double(Signal::TrendScorer) }

        it 'returns nil' do
          expect(selector.select_best_index).to be_nil
        end
      end

      context 'when one index scores above minimum' do
        before do
          nifty_scorer = instance_double(Signal::TrendScorer)
          banknifty_scorer = instance_double(Signal::TrendScorer)
          sensex_scorer = instance_double(Signal::TrendScorer)

          allow(Signal::TrendScorer).to receive(:new).with(
            instrument: nifty_instrument,
            primary_tf: '1m',
            confirmation_tf: '5m'
          ).and_return(nifty_scorer)
          allow(Signal::TrendScorer).to receive(:new).with(
            instrument: banknifty_instrument,
            primary_tf: '1m',
            confirmation_tf: '5m'
          ).and_return(banknifty_scorer)
          allow(Signal::TrendScorer).to receive(:new).with(
            instrument: sensex_instrument,
            primary_tf: '1m',
            confirmation_tf: '5m'
          ).and_return(sensex_scorer)

          allow(nifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 20.0, breakdown: { pa: 5, ind: 6, mtf: 6, vol: 3 } }
          )
          allow(banknifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 10.0, breakdown: { pa: 2, ind: 3, mtf: 3, vol: 2 } }
          )
          allow(sensex_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 12.0, breakdown: { pa: 3, ind: 4, mtf: 3, vol: 2 } }
          )
        end

        it 'returns the qualified index' do
          result = selector.select_best_index
          expect(result).to be_a(Hash)
          expect(result[:index_key]).to eq(:NIFTY)
          expect(result[:trend_score]).to eq(20.0)
        end
      end

      context 'when multiple indices score above minimum' do
        before do
          nifty_scorer = instance_double(Signal::TrendScorer)
          banknifty_scorer = instance_double(Signal::TrendScorer)
          sensex_scorer = instance_double(Signal::TrendScorer)

          allow(Signal::TrendScorer).to receive(:new).and_return(nifty_scorer, banknifty_scorer, sensex_scorer)

          allow(nifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 18.0, breakdown: { pa: 5, ind: 5, mtf: 5, vol: 3 } }
          )
          allow(banknifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 20.0, breakdown: { pa: 6, ind: 6, mtf: 6, vol: 2 } }
          )
          allow(sensex_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 16.0, breakdown: { pa: 4, ind: 4, mtf: 5, vol: 3 } }
          )
        end

        it 'returns the index with highest trend score' do
          result = selector.select_best_index
          expect(result[:index_key]).to eq(:BANKNIFTY)
          expect(result[:trend_score]).to eq(20.0)
        end
      end

      context 'when scores are close (tie-breaker scenario)' do
        before do
          nifty_scorer = instance_double(Signal::TrendScorer)
          banknifty_scorer = instance_double(Signal::TrendScorer)

          allow(Signal::TrendScorer).to receive(:new).and_return(nifty_scorer, banknifty_scorer)

          allow(nifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 18.0, breakdown: { pa: 5, ind: 5, mtf: 5, vol: 3 } }
          )
          allow(banknifty_scorer).to receive(:compute_trend_score).and_return(
            { trend_score: 18.5, breakdown: { pa: 6, ind: 5, mtf: 5, vol: 2.5 } }
          )

          # Mock volume for tie-breaker
          allow(nifty_instrument).to receive(:respond_to?).with(:candle_series).and_return(true)
          allow(banknifty_instrument).to receive(:respond_to?).with(:candle_series).and_return(true)
          allow(nifty_instrument).to receive(:candle_series).and_return(nil)
          allow(banknifty_instrument).to receive(:candle_series).and_return(nil)
        end

        it 'applies tie-breakers' do
          result = selector.select_best_index
          expect(result).to be_a(Hash)
          expect(result[:index_key]).to be_in([:NIFTY, :BANKNIFTY])
        end
      end
    end

    context 'when error occurs' do
      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_raise(StandardError, 'Test error')
      end

      it 'handles errors gracefully' do
        expect(selector.select_best_index).to be_nil
      end
    end
  end

  describe 'private methods' do
    describe '#score_all_indices' do
      let(:indices) do
        [
          { key: :NIFTY, segment: 'IDX_I', sid: '13' }
        ]
      end

      let(:instrument) { instance_double(Instrument) }
      let(:scorer) { instance_double(Signal::TrendScorer) }

      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
        allow(Signal::TrendScorer).to receive(:new).and_return(scorer)
        allow(scorer).to receive(:compute_trend_score).and_return(
          { trend_score: 18.0, breakdown: { pa: 5, ind: 5, mtf: 5, vol: 3 } }
        )
      end

      it 'scores indices correctly' do
        result = selector.send(:score_all_indices, indices)
        expect(result).to be_an(Array)
        expect(result.first[:index_key]).to eq(:NIFTY)
        expect(result.first[:trend_score]).to eq(18.0)
      end
    end

    describe '#apply_tie_breakers' do
      let(:qualified) do
        [
          { index_key: :NIFTY, trend_score: 18.0, breakdown: { pa: 5, ind: 5, mtf: 5, vol: 3 }, instrument: nil },
          { index_key: :BANKNIFTY, trend_score: 18.5, breakdown: { pa: 6, ind: 5, mtf: 5, vol: 2.5 }, instrument: nil }
        ]
      end

      it 'selects best index from qualified candidates' do
        result = selector.send(:apply_tie_breakers, qualified)
        expect(result).to be_a(Hash)
        expect(result[:index_key]).to be_in([:NIFTY, :BANKNIFTY])
        expect(result[:reason]).to be_present
      end
    end
  end
end


# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainAnalyzer do
  describe 'StrikePickResult' do
    it 'is successful when picks are present' do
      r = described_class::StrikePickResult.new([{ symbol: 'X' }], nil, nil)
      expect(r.success?).to be true
    end

    it 'is not successful when picks are empty' do
      r = described_class::StrikePickResult.new([], 'x', 'y')
      expect(r.success?).to be false
    end
  end

  describe '.pick_strikes_with_qualification' do
    let(:index_cfg) { { key: 'NIFTY' } }

    context 'when index instrument is missing' do
      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nil)
      end

      it 'returns no_instrument with reason mentioning index' do
        result = described_class.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: :bullish,
          permission: :scale_ready,
          expected_spot_move: 120.0
        )
        expect(result.picks).to eq([])
        expect(result.failure_code).to eq('no_instrument')
        expect(result.failure_reason).to include('NIFTY')
      end
    end

    context 'when expiry list is empty' do
      let(:instrument) { instance_double(Instrument, expiry_list: []) }

      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(instrument)
      end

      it 'returns no_expiry_list' do
        result = described_class.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: :bullish,
          permission: :scale_ready,
          expected_spot_move: 120.0
        )
        expect(result.failure_code).to eq('no_expiry_list')
        expect(result.failure_reason).to include('expiry')
      end
    end

    context 'when expected spot move is not positive' do
      let(:expiry) { 1.week.from_now.to_date }
      let(:instrument) do
        instance_double(
          Instrument,
          expiry_list: [expiry],
          symbol_name: 'NIFTY'
        )
      end

      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(instrument)
        allow(instrument).to receive(:fetch_option_chain).and_return(
          { oc: { '24000.0' => { 'ce' => {}, 'pe' => {} } }, last_price: 24_000.0 }
        )
      end

      it 'returns expected_move_non_positive after spot is available' do
        result = described_class.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: :bullish,
          permission: :scale_ready,
          expected_spot_move: 0.0
        )
        expect(result.failure_code).to eq('expected_move_non_positive')
        expect(result.failure_reason).to match(/ATR|non-positive/i)
      end
    end
  end
end

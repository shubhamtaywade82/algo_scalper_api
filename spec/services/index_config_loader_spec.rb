# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndexConfigLoader do
  subject(:loader) { described_class.instance }

  before do
    loader.clear_cache!
    allow(loader).to receive(:watchlist_table_exists?).and_return(true)
  end

  describe '.load_indices' do
    context 'when watchlist index row has wrong derivative segment' do
      let!(:instrument) { create(:instrument, :nifty_index) }

      before do
        create(:watchlist_item, :nifty_index, segment: 'NSE_FNO', watchable: instrument, label: 'NIFTY')
        allow(AlgoConfig).to receive(:fetch).and_return(
          indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13', lot: 75 }]
        )
      end

      it 'normalizes segment to IDX_I' do
        indices = described_class.load_indices
        nifty = indices.find { |idx| idx[:key] == 'NIFTY' }

        expect(nifty).to be_present
        expect(nifty[:segment]).to eq('IDX_I')
        expect(nifty[:sid]).to eq('13')
      end
    end

    context 'when watchlist is empty' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          indices: [
            { key: 'NIFTY', segment: 'IDX_I', sid: '13' },
            { key: 'BANKNIFTY', segment: 'IDX_I', sid: '25' },
            { key: 'SENSEX', segment: 'IDX_I', sid: '51' }
          ]
        )
      end

      it 'returns algo.yml indices with IDX_I segments' do
        indices = described_class.load_indices

        expect(indices).to contain_exactly(
          include(key: 'NIFTY', segment: 'IDX_I'),
          include(key: 'BANKNIFTY', segment: 'IDX_I'),
          include(key: 'SENSEX', segment: 'IDX_I')
        )
      end
    end
  end
end

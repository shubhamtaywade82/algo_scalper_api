# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::InstrumentLookupGuard do
  describe '.call' do
    let(:index_cfg) { { key: 'BANKNIFTY', sid: '25', segment: 'IDX_I' } }
    let(:context)   { { index_cfg: index_cfg } }
    let(:instrument) { instance_double(Instrument) }
    let(:cache) { instance_double(IndexInstrumentCache) }

    before do
      allow(IndexInstrumentCache).to receive(:instance).and_return(cache)
    end

    context 'when IndexInstrumentCache resolves the instrument' do
      before { allow(cache).to receive(:get_or_fetch).with(index_cfg).and_return(instrument) }

      it 'sets instrument on context and passes' do
        result = described_class.call(context)

        expect(context[:instrument]).to eq(instrument)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when IndexInstrumentCache returns nil' do
      before { allow(cache).to receive(:get_or_fetch).with(index_cfg).and_return(nil) }

      it 'blocks with instrument not found message' do
        result = described_class.call(context)

        expect(result).to include(blocked: 'instrument not found for BANKNIFTY')
      end
    end
  end
end

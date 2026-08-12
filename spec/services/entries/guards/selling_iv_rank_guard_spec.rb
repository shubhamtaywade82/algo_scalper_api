# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::SellingIvRankGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { iv: current_iv } }
  let(:current_iv) { 10.5 }

  def build_context(position_side: 'short')
    { index_cfg: index_cfg, pick: pick, position_side: position_side }
  end

  it 'passes for a long (buying) entry regardless of IV' do
    expect(described_class.call(build_context(position_side: 'long'))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'passes when there is not enough IV history to rank against' do
    allow(IvSnapshot).to receive(:historical_iv).and_return([10.0, 12.0])

    expect(described_class.call(build_context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  context 'with sufficient IV history' do
    before do
      allow(IvSnapshot).to receive(:historical_iv).and_return([10.0, 12.0, 14.0, 16.0, 18.0])
    end

    it 'blocks selling when current IV rank is low' do
      result = described_class.call(build_context)

      expect(result).to be_a(Hash)
      expect(result[:blocked]).to include('too low')
    end

    context 'when current IV is at the top of the recent range' do
      let(:current_iv) { 30.0 }

      it 'passes' do
        expect(described_class.call(build_context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end

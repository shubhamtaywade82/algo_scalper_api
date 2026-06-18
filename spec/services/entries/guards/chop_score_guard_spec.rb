# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::ChopScoreGuard do
  let(:instrument) { instance_double(Instrument) }
  let(:context) do
    {
      index_cfg: { key: 'NIFTY' },
      instrument: instrument,
      entry_metadata: {}
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      { signals: { chop_score: { enabled: true, block_threshold: 5 } } }
    )
    allow(instrument).to receive(:candle_series).and_return(nil)
    allow(Entries::ChopScore).to receive(:new).and_return(
      instance_double(Entries::ChopScore, call: { score: 0, action: :allow, reasons: [] })
    )
  end

  it 'passes when chop score is below block threshold' do
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:entry_metadata][:chop_action]).to eq('allow')
  end

  it 'blocks when chop score action is block' do
    allow(Entries::ChopScore).to receive(:new).and_return(
      instance_double(
        Entries::ChopScore,
        call: { score: 6, action: :block, reasons: ['5m ADX below trend threshold'] }
      )
    )

    result = described_class.call(context)

    expect(result[:blocked]).to include('chop_score=6')
  end

  it 'passes when the guard is disabled' do
    allow(AlgoConfig).to receive(:fetch).and_return(
      { signals: { chop_score: { enabled: false } } }
    )

    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end
end

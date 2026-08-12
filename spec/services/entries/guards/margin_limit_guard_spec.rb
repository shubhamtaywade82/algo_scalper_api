# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::MarginLimitGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { security_id: '12345', segment: 'NSE_FNO', ltp: BigDecimal('100.0'), lot_size: 75 } }
  let(:context) { { index_cfg: index_cfg, pick: pick, position_side: 'short' } }
  let(:margin_adapter) { instance_double(Adapters::Margin::DhanMarginAdapter) }

  before do
    described_class.instance_variable_set(:@margin_adapter, margin_adapter)
    allow(Capital::Allocator).to receive(:available_cash).and_return(BigDecimal('100000'))
  end

  after do
    described_class.instance_variable_set(:@margin_adapter, nil)
  end

  it 'passes for a long (buying) entry regardless of margin' do
    expect(described_class.call(context.merge(position_side: 'long'))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'passes when 1 lot fits the margin budget' do
    allow(margin_adapter).to receive(:margin_for).and_return(BigDecimal('20000'))

    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'blocks when even 1 lot exceeds the margin budget' do
    allow(margin_adapter).to receive(:margin_for).and_return(BigDecimal('60000'))

    result = described_class.call(context)

    expect(result).to be_a(Hash)
    expect(result[:blocked]).to include('margin')
  end

  it 'fails open when the margin API is unavailable' do
    allow(margin_adapter).to receive(:margin_for).and_return(nil)

    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end
end

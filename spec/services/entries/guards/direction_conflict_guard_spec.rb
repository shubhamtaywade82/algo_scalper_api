# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::DirectionConflictGuard do
  let(:index_cfg) { { key: 'NIFTY' } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
  end

  it 'passes without touching positions for a selling entry' do
    context = { index_cfg: index_cfg, direction: :bullish, position_side: 'short' }

    expect(described_class).not_to receive(:position_scope) # rubocop:disable RSpec/MessageSpies -- negative expectation, no prior stub to spy on
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'does not force-close a losing short position when a long entry is attempted' do
    short_tracker = create(:position_tracker, index_key: 'NIFTY', side: 'short_pe', position_side: 'short',
                                              status: 'active', paper: true, last_pnl_rupees: -500)
    allow_any_instance_of(PositionTracker).to receive(:current_pnl_rupees).and_return(-500.0) # rubocop:disable RSpec/AnyInstance
    allow(Live::ExitEngine).to receive(:new).and_call_original

    described_class.call({ index_cfg: index_cfg, direction: :bullish, position_side: 'long' })

    expect(short_tracker.reload.status).to eq('active')
  end
end

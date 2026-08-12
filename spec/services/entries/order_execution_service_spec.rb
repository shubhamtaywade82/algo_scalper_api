# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::OrderExecutionService do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO' } }
  let(:pick) { { symbol: 'NIFTY24MAR22000CE', security_id: '12345', segment: 'NSE_FNO' } }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: 'NSE', segment: 'index', security_id: '13') }
  let(:command_result) { instance_double(Orders::Commands::CommandResult, success?: true, payload: { raw: { success: true, order_id: 'PAPER-1', paper: true } }) }

  before do
    allow(Orders::Commands::PlaceOrderCommand).to receive(:new).and_call_original
    allow_any_instance_of(Orders::Commands::PlaceOrderCommand).to receive(:call).and_return(command_result) # rubocop:disable RSpec/AnyInstance
    allow(Entries::EntryGuard).to receive(:create_paper_tracker!).and_return(create(:position_tracker, instrument: instrument, paper: true))
    allow(Ledger::EntryPoster).to receive(:post!)
  end

  def call_with(side)
    context = { index_cfg: index_cfg, pick: pick, instrument: instrument, side: side, quantity: 25, ltp: BigDecimal('100.0') }
    described_class.call(context)
  end

  it 'places a BUY order for a long side' do
    call_with('long_ce')

    expect(Orders::Commands::PlaceOrderCommand).to have_received(:new).with(hash_including(side: :buy))
  end

  it 'places a SELL order for a short side (sell-to-open)' do
    call_with('short_pe')

    expect(Orders::Commands::PlaceOrderCommand).to have_received(:new).with(hash_including(side: :sell))
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::TransactionCostGuard do
  let(:tick) { instance_double(MarketTick, bid: 99.5, ask: 100.5) }
  let(:instrument) { instance_double(Instrument, lot_size: 50) }
  let(:context) do
    {
      ltp: 100.0,
      index_cfg: { key: 'NIFTY', segment: 'NSE_FNO' },
      pick: { security_id: 'opt1', segment: 'NSE_FNO' },
      instrument: instrument
    }
  end

  # spread_pct = (100.5-99.5)/100 = 0.01 ; slippage = 0.002 ; fees = 40/(100*50)=0.008
  # → round-trip cost = 0.020
  def configure(execution)
    allow(OptionsBuying::Mode).to receive(:config).and_return(execution: execution)
    allow(AlgoConfig).to receive(:fetch).and_return(broker_fees: { enabled: true, fee_per_order: 20 })
    allow(Live::TickQuery).to receive(:for_security).and_return(tick)
  end

  it 'passes (no-op) when the TCM gate is disabled' do
    configure(tcm_enabled: false)
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'passes when expected edge clears the round-trip cost' do
    configure(tcm_enabled: true, expected_edge_pct: 0.30)
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'blocks when the round-trip cost exceeds the expected edge' do
    configure(tcm_enabled: true, expected_edge_pct: 0.01) # edge 0.01 < cost 0.02
    expect(described_class.call(context)[:blocked]).to include('transaction cost exceeds edge')
  end

  it 'prefers a per-signal injected edge over config' do
    configure(tcm_enabled: true, expected_edge_pct: 0.01)
    expect(described_class.call(context.merge(expected_edge_pct: 0.50))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'honours the min_net_edge_pct buffer' do
    configure(tcm_enabled: true, expected_edge_pct: 0.025, min_net_edge_pct: 0.02)
    # net = 0.025 - 0.020 = 0.005, below the 0.02 buffer → block
    expect(described_class.call(context)[:blocked]).to include('transaction cost')
  end

  it 'ignores fees when lot_size is unavailable (spread + slippage only)' do
    configure(tcm_enabled: true, expected_edge_pct: 0.013) # cost without fees = 0.012
    allow(instrument).to receive(:lot_size).and_return(0)
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'fails open when a dependency raises' do
    configure(tcm_enabled: true, expected_edge_pct: 0.01)
    allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError, 'down')
    # spread lookup raising is rescued inside the guard → treated as zero spread, still evaluates;
    # force a harder failure on config read to hit the outer rescue
    allow(OptionsBuying::Mode).to receive(:config).and_raise(StandardError, 'boom')
    expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
  end
end

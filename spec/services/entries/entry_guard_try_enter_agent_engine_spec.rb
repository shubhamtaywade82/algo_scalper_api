# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard, '#try_enter agent engine' do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:pick) { { symbol: 'NIFTY-26000-CE', security_id: '47895', segment: 'NSE_FNO' } }
  let(:intent) { instance_double(TradeIntent, intent_id: 'abc') }
  let(:signal) { instance_double(Strategies::Signal, confidence: 0.8, record_entry_outcome: true) }

  before do
    allow(TradeIntents::Forwarder).to receive_messages(agent_engine?: true,
                                                       forward: TradeIntents::Forwarder::Result.new(intent: intent, blocked_reason: nil))
    allow(described_class.entry_guard_pipeline).to receive(:run)
  end

  def try_enter(position_side: 'long')
    described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: :bullish, signal: signal,
                              entry_metadata: { entry_contract: 'supertrend_machine_v1' }, position_side: position_side)
  end

  it 'forwards the signal to the agent instead of running the Rails entry pipeline' do
    expect(try_enter).to be(false)

    expect(TradeIntents::Forwarder).to have_received(:forward)
      .with(index_cfg: index_cfg, direction: :bullish, signal: { strategy: 'supertrend_machine_v1', confidence: 0.8 })
    expect(signal).to have_received(:record_entry_outcome).with('blocked', 'forwarded_to_agent:abc')
    expect(described_class.entry_guard_pipeline).not_to have_received(:run)
  end

  it 'never turns an option-selling signal into a buy intent' do
    expect(try_enter(position_side: 'short')).to be(false)

    expect(TradeIntents::Forwarder).not_to have_received(:forward)
    expect(signal).to have_received(:record_entry_outcome).with('blocked', 'agent_engine_buy_only')
  end

  it 'delegates non-agent direct order execution to Entries::DirectOrderPlacer' do
    allow(TradeIntents::Forwarder).to receive(:agent_engine?).and_return(false)
    allow(described_class.entry_guard_pipeline).to receive(:run).and_return(Entries::EntryGuardPipeline::PASS)
    allow(Entries::DirectOrderPlacer).to receive(:execute).and_return(:order_placed)
    expect(try_enter).to eq(:order_placed)
  end
end

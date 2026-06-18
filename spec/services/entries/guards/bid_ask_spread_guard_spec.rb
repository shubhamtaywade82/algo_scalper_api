# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::BidAskSpreadGuard do
  let(:context) do
    {
      index_cfg: { key: 'NIFTY', segment: 'IDX_I' },
      pick: { security_id: '123', segment: 'NSE_FNO' },
      ltp: 100.0
    }
  end

  before do
    allow(OptionsBuying::Mode).to receive(:config).and_return(
      execution: { spread_enabled: true, max_bid_ask_spread_pct: 0.015 }
    )
  end

  context 'when spread guard is disabled in config' do
    before do
      allow(OptionsBuying::Mode).to receive(:config).and_return(
        execution: { spread_enabled: false, max_bid_ask_spread_pct: 0.015 }
      )
    end

    it 'passes without checking the tick' do
      expect(Live::TickQuery).not_to receive(:for_security)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when spread is within limit' do
    before do
      tick = instance_double(MarketTick, bid: 99.5, ask: 100.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)
    end

    it 'passes' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when spread is too wide' do
    before do
      tick = instance_double(MarketTick, bid: 95.0, ask: 100.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)
    end

    it 'blocks entry' do
      result = described_class.call(context)

      expect(result[:blocked]).to include('bid-ask spread too wide')
    end
  end
end

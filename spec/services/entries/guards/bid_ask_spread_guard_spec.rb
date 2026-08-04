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

  context 'when index override allows wider spread' do
    let(:context) do
      {
        index_cfg: { key: 'SENSEX', segment: 'IDX_I', execution: { max_bid_ask_spread_pct: 0.025 } },
        pick: { security_id: '123', segment: 'BSE_FNO' },
        ltp: 100.0
      }
    end

    before do
      tick = instance_double(MarketTick, bid: 97.6, ask: 100.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)
    end

    it 'passes within the Sensex-specific threshold' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when quantity filter is enabled and tick is shallow' do
    before do
      allow(OptionsBuying::Mode).to receive(:config).and_return(
        execution: { spread_enabled: true, max_bid_ask_spread_pct: 0.015, min_bid_qty: 100, min_ask_qty: 100 }
      )
    end

    it 'blocks on shallow bid quantity' do
      tick = instance_double(MarketTick, bid: 99.5, ask: 100.0, bid_qty: 50, ask_qty: 500)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      result = described_class.call(context)
      expect(result[:blocked]).to include('bid quantity too shallow')
    end

    it 'blocks on shallow ask quantity' do
      tick = instance_double(MarketTick, bid: 99.5, ask: 100.0, bid_qty: 500, ask_qty: 50)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      result = described_class.call(context)
      expect(result[:blocked]).to include('ask quantity too shallow')
    end

    it 'passes when both bid and ask quantities are sufficient' do
      tick = instance_double(MarketTick, bid: 99.5, ask: 100.0, bid_qty: 200, ask_qty: 300)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when quantity filter is enabled but tick lacks quantity data' do
    before do
      allow(OptionsBuying::Mode).to receive(:config).and_return(
        execution: { spread_enabled: true, max_bid_ask_spread_pct: 0.015, min_bid_qty: 100, min_ask_qty: 100 }
      )
    end

    it 'passes open when quantity fields are missing' do
      tick = instance_double(MarketTick, bid: 99.5, ask: 100.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end
end

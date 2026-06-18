# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::LtpResolutionGuard do
  let(:instrument) { instance_double(Instrument) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I' } }
  let(:pick) { { symbol: 'NIFTY25000CE', security_id: '50074', segment: 'NSE_FNO', ltp: 98.0 } }
  let(:context) { { pick: pick, instrument: instrument, index_cfg: index_cfg } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ realtime: { entry_ltp_max_age_seconds: 2 } })
    allow(Live::MarketFeedHub.instance).to receive_messages(running?: true, connected?: true)
  end

  it 'uses fresh tick cache LTP for entry even when pick contains ltp' do
    allow(Live::TickQuery).to receive(:for_security).and_return(build_tick(ltp: '102.5', age_seconds: 0.2))
    allow(described_class).to receive(:resolve_entry_ltp)

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('102.5'))
    expect(described_class).not_to have_received(:resolve_entry_ltp)
  end

  it 'accepts tick after forced refresh when subscribe yields no fresh tick but cache updates' do
    allow(described_class).to receive(:resolve_entry_ltp).and_return({ ltp: nil, transport: :none })
    allow(Live::TickQuery).to receive(:for_security).and_return(
      build_tick(ltp: '99.0', age_seconds: 5.0),
      build_tick(ltp: '101.0', age_seconds: 0.1)
    )

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('101.0'))
  end

  it 'accepts REST snapshot when tick cache stays stale' do
    allow(described_class).to receive(:resolve_entry_ltp).and_return(
      { ltp: BigDecimal('250.45'), transport: :rest_derivative }
    )
    stale = build_tick(ltp: '99.0', age_seconds: 6.0)
    allow(Live::TickQuery).to receive(:for_security).and_return(stale, stale)

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('250.45'))
  end

  it 'accepts websocket_fresh resolution when re-read tick lags' do
    allow(described_class).to receive(:resolve_entry_ltp).and_return(
      { ltp: BigDecimal('180.25'), transport: :websocket_fresh }
    )
    stale = build_tick(ltp: '99.0', age_seconds: 6.0)
    allow(Live::TickQuery).to receive(:for_security).and_return(stale, stale)

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('180.25'))
  end

  it 'blocks entry when no fresh tick and no usable resolution' do
    allow(described_class).to receive(:resolve_entry_ltp).and_return({ ltp: nil, transport: :none })
    stale = build_tick(ltp: '99.0', age_seconds: 6.0)
    allow(Live::TickQuery).to receive(:for_security).and_return(stale, stale)

    result = described_class.call(context)

    expect(result).to be_a(Hash)
    expect(result[:blocked]).to include('fresh_ltp_unavailable')
  end

  def build_tick(ltp:, age_seconds:)
    MarketTick.new(
      segment: 'NSE_FNO',
      security_id: '50074',
      ltp: BigDecimal(ltp.to_s),
      timestamp: Time.current - age_seconds,
      oi: 0,
      oi_change: 0,
      bid: nil,
      ask: nil,
      volume: 0,
      prev_close: nil
    )
  end
end

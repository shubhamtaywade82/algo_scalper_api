# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::LtpResolutionGuard do
  let(:instrument) { instance_double(Instrument) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO' } }
  let(:pick) { { symbol: 'NIFTY25000CE', security_id: '50074', segment: 'NSE_FNO', ltp: 98.0 } }
  let(:context) { { pick: pick, instrument: instrument, index_cfg: index_cfg } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ realtime: { entry_ltp_max_age_seconds: 2 } })
    allow(Live::MarketFeedHub.instance).to receive_messages(running?: true, connected?: true)
  end

  it 'uses fresh tick cache LTP for entry even when pick contains ltp' do
    allow(Live::TickQuery).to receive(:for_security).and_return(build_tick(ltp: '102.5', age_seconds: 0.2))
    allow(Entries::EntryGuard).to receive(:resolve_entry_ltp)

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('102.5'))
    expect(Entries::EntryGuard).not_to have_received(:resolve_entry_ltp)
  end

  it 'uses forced refresh path when initial tick is stale and accepts fresh refreshed tick' do
    allow(Live::TickQuery).to receive(:for_security).and_return(
      build_tick(ltp: '99.0', age_seconds: 5.0),
      build_tick(ltp: '101.0', age_seconds: 0.1)
    )
    allow(Entries::EntryGuard).to receive(:resolve_entry_ltp).and_return(BigDecimal('101.0'))

    result = described_class.call(context)

    expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    expect(context[:ltp]).to eq(BigDecimal('101.0'))
    expect(Entries::EntryGuard).to have_received(:resolve_entry_ltp).once
  end

  it 'blocks entry when no fresh tick is available after forced refresh' do
    allow(Live::TickQuery).to receive(:for_security).and_return(
      build_tick(ltp: '99.0', age_seconds: 6.0),
      build_tick(ltp: '99.0', age_seconds: 6.0)
    )
    allow(Entries::EntryGuard).to receive(:resolve_entry_ltp).and_return(BigDecimal('100.0'))

    result = described_class.call(context)

    expect(result).to be_a(Hash)
    expect(result[:blocked]).to include('fresh_ltp_unavailable')
  end

  context 'when the max-age knob is misconfigured (wave 3)' do
    it 'blocks with a configuration failure instead of silently using the default' do
      allow(AlgoConfig).to receive(:fetch).and_return({ realtime: { entry_ltp_max_age_seconds: 'soon' } })

      result = described_class.call(context)

      expect(result).to be_a(Hash)
      expect(result[:blocked]).to include('ltp_resolution_failed')
    end

    it 'blocks when the configured max age is not positive' do
      allow(AlgoConfig).to receive(:fetch).and_return({ realtime: { entry_ltp_max_age_seconds: 0 } })

      result = described_class.call(context)

      expect(result).to be_a(Hash)
      expect(result[:blocked]).to include('ltp_resolution_failed')
    end
  end

  context 'when the max-age knob is absent (documented default 2.0s)' do
    it 'uses the default window' do
      allow(AlgoConfig).to receive(:fetch).and_return({})
      allow(Live::TickQuery).to receive(:for_security).and_return(build_tick(ltp: '102.5', age_seconds: 0.2))
      allow(Entries::EntryGuard).to receive(:resolve_entry_ltp)

      result = described_class.call(context)

      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    end
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

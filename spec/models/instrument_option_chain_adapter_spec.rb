# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument do
  describe '.option_chain_adapter' do
    after do
      described_class.option_chain_adapter = nil
    end

    it 'defaults to Dhan adapter' do
      adapter = described_class.option_chain_adapter

      expect(adapter).to be_a(Adapters::OptionChain::DhanAdapter)
    end
  end

  describe '#fetch_fresh_option_chain' do
    let(:instrument) { described_class.new(security_id: '12345', exchange: 'nse', segment: 'derivatives') }
    let(:adapter) { instance_double(Adapters::OptionChain::DhanAdapter) }

    before do
      described_class.option_chain_adapter = adapter
    end

    after do
      described_class.option_chain_adapter = nil
    end

    it 'delegates option-chain fetch to configured adapter' do
      payload = {
        'last_price' => 120.5,
        'oc' => {
          '22000.0' => {
            'ce' => { 'oi' => 100_000, 'implied_volatility' => 15.0 },
            'pe' => { 'oi' => 95_000, 'implied_volatility' => 16.0 }
          }
        }
      }

      allow(adapter).to receive(:fetch_chain).and_return(payload)

      result = instrument.send(:fetch_fresh_option_chain, '2026-02-26')

      expect(adapter).to have_received(:fetch_chain).with(
        underlying_scrip: 12_345,
        underlying_seg: 'NSE_FNO',
        expiry: '2026-02-26'
      )
      expect(result).to include(last_price: 120.5)
    end
  end

  describe '#expiry_list' do
    let(:instrument) { described_class.new(security_id: '50074', exchange: 'nse', segment: 'index') }
    let(:adapter) { instance_double(Adapters::OptionChain::DhanAdapter) }

    before do
      described_class.option_chain_adapter = adapter
    end

    after do
      described_class.option_chain_adapter = nil
    end

    it 'delegates expiry-list fetch to configured adapter' do
      allow(adapter).to receive(:fetch_expiry_list).and_return(%w[2026-03-05 2026-03-12])

      result = instrument.expiry_list

      expect(adapter).to have_received(:fetch_expiry_list).with(
        underlying_scrip: 50_074,
        underlying_seg: 'IDX_I'
      )
      expect(result).to eq(%w[2026-03-05 2026-03-12])
    end
  end

  describe '#fetch_option_chain caching' do
    let(:instrument) { described_class.new(security_id: '12345', exchange: 'nse', segment: 'derivatives') }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:chain) { { last_price: 100.0, oc: {} } }
    let(:key) { 'option_chain:12345:2026-02-26' }

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      allow(AlgoConfig).to receive(:fetch).and_return({})
      allow(instrument).to receive(:fetch_fresh_option_chain).and_return(chain)
    end

    it 'fetches once and serves the cached chain while fresh' do
      2.times { instrument.fetch_option_chain('2026-02-26') }

      expect(instrument).to have_received(:fetch_fresh_option_chain).once
    end

    it 'serves the last good chain without calling the API when another process holds the refresh lock' do
      cache.write(key, chain)
      cache.write("#{key}:lock", true)

      expect(instrument.fetch_option_chain('2026-02-26')).to eq(chain)
      expect(instrument).not_to have_received(:fetch_fresh_option_chain)
    end

    it 'backs off after a failed refresh instead of retrying and keeps serving the stale chain' do
      cache.write(key, chain)
      allow(instrument).to receive(:fetch_fresh_option_chain).and_return(nil)

      2.times { expect(instrument.fetch_option_chain('2026-02-26')).to eq(chain) }

      expect(instrument).to have_received(:fetch_fresh_option_chain).once
    end

    it 'releases the lock after refreshing' do
      instrument.fetch_option_chain('2026-02-26')

      expect(cache.read("#{key}:lock")).to be_nil
    end
  end
end

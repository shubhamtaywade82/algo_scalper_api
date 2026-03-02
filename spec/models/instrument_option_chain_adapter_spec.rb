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
    let(:instrument) { described_class.new(security_id: '12345', exchange_segment: 'NSE_FNO') }
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
    let(:instrument) { described_class.new(security_id: '50074', exchange_segment: 'NSE_IDX') }
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
        underlying_seg: 'NSE_IDX'
      )
      expect(result).to eq(%w[2026-03-05 2026-03-12])
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::OptionChainWrapper do
  let(:index_key) { 'NIFTY' }

  describe '#initialize' do
    it 'handles nested option chain data with :oc key' do
      chain_data = { oc: { ce: {}, pe: {} } }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      expect(wrapper.chain_data).to eq(chain_data[:oc])
    end

    it 'handles nested option chain data with "oc" key' do
      chain_data = { 'oc' => { 'ce' => {}, 'pe' => {} } }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      expect(wrapper.chain_data).to eq(chain_data['oc'])
    end

    it 'handles direct option chain data' do
      chain_data = { ce: {}, pe: {} }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      expect(wrapper.chain_data).to eq(chain_data)
    end

    it 'handles nil chain data' do
      wrapper = described_class.new(chain_data: nil, index_key: index_key)

      expect(wrapper.chain_data).to eq({})
    end
  end

  describe '#ce_oi_rising?' do
    it 'returns true when ATM CE has positive OI' do
      chain_data = {
        ce: {
          '25000' => { 'oi' => 1000, 'ltp' => 100.0 },
          '25100' => { 'oi' => 2000, 'ltp' => 80.0 }
        },
        pe: {}
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['25000'])

      result = wrapper.ce_oi_rising?

      expect(result).to be true
    end

    it 'returns false when ATM CE has zero OI' do
      chain_data = {
        ce: {
          '25000' => { 'oi' => 0, 'ltp' => 100.0 }
        },
        pe: {}
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['25000'])

      result = wrapper.ce_oi_rising?

      expect(result).to be false
    end

    it 'returns false when chain data is invalid' do
      wrapper = described_class.new(chain_data: nil, index_key: index_key)

      result = wrapper.ce_oi_rising?

      expect(result).to be false
    end
  end

  describe '#pe_oi_rising?' do
    it 'returns true when ATM PE has positive OI' do
      chain_data = {
        ce: {},
        pe: {
          '25000' => { 'oi' => 1000, 'ltp' => 100.0 },
          '24900' => { 'oi' => 2000, 'ltp' => 80.0 }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).with(:pe).and_return(chain_data[:pe]['25000'])

      result = wrapper.pe_oi_rising?

      expect(result).to be true
    end

    it 'returns false when ATM PE has zero OI' do
      chain_data = {
        ce: {},
        pe: {
          '25000' => { 'oi' => 0, 'ltp' => 100.0 }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).with(:pe).and_return(chain_data[:pe]['25000'])

      result = wrapper.pe_oi_rising?

      expect(result).to be false
    end
  end

  describe '#atm_iv' do
    it 'returns ATM IV when available' do
      chain_data = {
        ce: {
          '25000' => { 'iv' => 15.5, 'ltp' => 100.0 }
        },
        pe: {}
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['25000'])

      iv = wrapper.atm_iv

      expect(iv).to eq(15.5)
    end

    it 'returns nil when ATM option not found' do
      wrapper = described_class.new(chain_data: {}, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).and_return(nil)

      iv = wrapper.atm_iv

      expect(iv).to be_nil
    end
  end

  describe '#iv_falling?' do
    it 'returns false (placeholder implementation)' do
      wrapper = described_class.new(chain_data: {}, index_key: index_key)

      result = wrapper.iv_falling?

      expect(result).to be false
    end
  end

  describe '#spread_wide?' do
    context 'for NIFTY' do
      it 'returns true when spread > 2' do
        chain_data = {
          ce: {
            '25000' => { 'bid' => 100.0, 'ask' => 103.0, 'ltp' => 101.0 }
          },
          pe: {}
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'NIFTY')
        allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['25000'])

        result = wrapper.spread_wide?

        expect(result).to be true
      end

      it 'returns false when spread <= 2' do
        chain_data = {
          ce: {
            '25000' => { 'bid' => 100.0, 'ask' => 101.5, 'ltp' => 100.5 }
          },
          pe: {}
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'NIFTY')
        allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['25000'])

        result = wrapper.spread_wide?

        expect(result).to be false
      end
    end

    context 'for BANKNIFTY' do
      it 'returns true when spread > 3' do
        chain_data = {
          ce: {
            '56000' => { 'bid' => 200.0, 'ask' => 204.0, 'ltp' => 202.0 }
          },
          pe: {}
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'BANKNIFTY')
        allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['56000'])

        result = wrapper.spread_wide?

        expect(result).to be true
      end

      it 'returns false when spread <= 3' do
        chain_data = {
          ce: {
            '56000' => { 'bid' => 200.0, 'ask' => 202.5, 'ltp' => 201.0 }
          },
          pe: {}
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'BANKNIFTY')
        allow(wrapper).to receive(:find_atm_option).with(:ce).and_return(chain_data[:ce]['56000'])

        result = wrapper.spread_wide?

        expect(result).to be false
      end
    end

    it 'returns false when ATM option not found' do
      wrapper = described_class.new(chain_data: {}, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).and_return(nil)

      result = wrapper.spread_wide?

      expect(result).to be false
    end
  end
end

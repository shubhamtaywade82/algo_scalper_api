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
    it 'returns true when ATM CE OI is higher than previous OI' do
      chain_data = {
        last_price: 25_010,
        oc: {
          '25000' => {
            'ce' => { 'oi' => 1000, 'previous_oi' => 900, 'last_price' => 100.0 },
            'pe' => { 'oi' => 800, 'previous_oi' => 850, 'last_price' => 95.0 }
          },
          '25100' => {
            'ce' => { 'oi' => 2000, 'previous_oi' => 2050, 'last_price' => 80.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      result = wrapper.ce_oi_rising?

      expect(result).to be true
    end

    it 'returns false when previous OI is missing or not lower' do
      chain_data = {
        last_price: 25_000,
        oc: {
          '25000' => {
            'ce' => { 'oi' => 1000, 'previous_oi' => 1000, 'last_price' => 100.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

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
    it 'returns true when ATM PE OI is higher than previous OI' do
      chain_data = {
        last_price: 24_995,
        oc: {
          '25000' => {
            'ce' => { 'oi' => 900, 'previous_oi' => 920, 'last_price' => 101.0 },
            'pe' => { 'oi' => 1000, 'previous_oi' => 950, 'last_price' => 100.0 }
          },
          '24900' => {
            'pe' => { 'oi' => 2000, 'previous_oi' => 2100, 'last_price' => 80.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      result = wrapper.pe_oi_rising?

      expect(result).to be true
    end

    it 'returns false when ATM PE has zero OI' do
      chain_data = {
        last_price: 25_000,
        oc: {
          '25000' => {
            'pe' => { 'oi' => 0, 'previous_oi' => 100, 'last_price' => 100.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      result = wrapper.pe_oi_rising?

      expect(result).to be false
    end
  end

  describe '#atm_iv' do
    it 'returns ATM IV when available' do
      chain_data = {
        last_price: 25_000,
        oc: {
          '25000' => {
            'ce' => { 'implied_volatility' => 15.0, 'last_price' => 100.0 },
            'pe' => { 'implied_volatility' => 16.0, 'last_price' => 101.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

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
    it 'returns true when ATM IV is lower than previous IV' do
      chain_data = {
        last_price: 25_000,
        oc: {
          '25000' => {
            'ce' => {
              'implied_volatility' => 14.5,
              'previous_implied_volatility' => 15.2,
              'last_price' => 100.0
            }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      result = wrapper.iv_falling?

      expect(result).to be true
    end
  end

  describe '#spread_wide?' do
    context 'for NIFTY' do
      it 'returns true when spread > 3' do
        chain_data = {
          last_price: 25_000,
          oc: {
            '25000' => {
              'ce' => { 'top_bid_price' => 100.0, 'top_ask_price' => 104.0, 'last_price' => 101.0 }
            }
          }
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'NIFTY')

        result = wrapper.spread_wide?

        expect(result).to be true
      end

      it 'returns false when spread <= 2' do
        chain_data = {
          last_price: 25_000,
          oc: {
            '25000' => {
              'ce' => { 'top_bid_price' => 100.0, 'top_ask_price' => 101.5, 'last_price' => 100.5 }
            }
          }
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'NIFTY')

        result = wrapper.spread_wide?

        expect(result).to be false
      end
    end

    context 'for BANKNIFTY' do
      it 'returns true when spread > 3' do
        chain_data = {
          last_price: 56_000,
          oc: {
            '56000' => {
              'ce' => { 'top_bid_price' => 200.0, 'top_ask_price' => 204.0, 'last_price' => 202.0 }
            }
          }
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'BANKNIFTY')

        result = wrapper.spread_wide?

        expect(result).to be true
      end

      it 'returns false when spread <= 3' do
        chain_data = {
          last_price: 56_000,
          oc: {
            '56000' => {
              'ce' => { 'top_bid_price' => 200.0, 'top_ask_price' => 202.5, 'last_price' => 201.0 }
            }
          }
        }

        wrapper = described_class.new(chain_data: chain_data, index_key: 'BANKNIFTY')

        result = wrapper.spread_wide?

        expect(result).to be false
      end
    end

    it 'returns true when ATM option not found to fail closed on missing liquidity data' do
      wrapper = described_class.new(chain_data: {}, index_key: index_key)
      allow(wrapper).to receive(:find_atm_option).and_return(nil)

      result = wrapper.spread_wide?

      expect(result).to be true
    end
  end

  describe 'ATM selection' do
    it 'uses the closest strike to spot price instead of the first priced option' do
      chain_data = {
        last_price: 25_040,
        oc: {
          '24900' => {
            'ce' => { 'last_price' => 150.0 },
            'pe' => { 'last_price' => 60.0 }
          },
          '25000' => {
            'ce' => { 'last_price' => 102.0, 'oi' => 1000, 'previous_oi' => 900 },
            'pe' => { 'last_price' => 98.0 }
          },
          '25100' => {
            'ce' => { 'last_price' => 70.0 },
            'pe' => { 'last_price' => 130.0 }
          }
        }
      }

      wrapper = described_class.new(chain_data: chain_data, index_key: index_key)

      expect(wrapper.send(:find_atm_option, :ce)).to eq(chain_data[:oc]['25000']['ce'])
    end
  end
end

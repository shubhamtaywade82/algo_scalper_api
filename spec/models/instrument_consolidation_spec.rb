# frozen_string_literal: true

require 'rails_helper'

# Consolidated instrument master: identity, contract resolution and the
# underlying self-reference (architecture review 2026-09).
RSpec.describe Instrument do
  describe 'canonical broker identity' do
    it 'rejects a duplicate security_id within the same exchange segment' do
      create(:instrument, :nifty_index, security_id: '13')

      dupe = build(:instrument, :nifty_index, security_id: '13', symbol_name: 'NIFTY-RENAMED')

      expect(dupe).not_to be_valid
      expect(dupe.errors[:security_id]).to be_present
    end

    it 'allows the same security_id across different exchange segments' do
      create(:instrument, :nifty_index, security_id: '13')

      other = build(:instrument, security_id: '13', segment: 'equity', symbol_name: 'OTHER')

      expect(other).to be_valid
    end
  end

  describe 'underlying self-reference' do
    it 'links derivative contracts to their underlying instrument' do
      underlying = create(:instrument, :nifty_index, security_id: '13')
      option = create(:instrument, :nifty_call_option, underlying_security_id: '13')
      option.update!(underlying_instrument: underlying)

      expect(option.underlying_instrument).to eq(underlying)
      expect(underlying.derivative_contracts).to include(option)
      expect(underlying.derivatives).to include(option) # back-compat alias
    end
  end

  describe 'predicates' do
    it 'classifies options, futures and plain instruments' do
      option = build(:instrument, :nifty_call_option)
      future = build(:instrument, :nifty_future, strike_price: nil)
      index = build(:instrument, :nifty_index, underlying_security_id: nil)

      expect(option).to be_option
      expect(option).to be_derivative
      expect(future).to be_future
      expect(future).to be_derivative
      expect(index).not_to be_derivative
      expect(index).to be_index_master
    end

    it 'flags expired contracts and excludes them from current tradability' do
      expired = build(:instrument, :nifty_call_option, expiry_date: 1.day.ago)
      live_contract = build(:instrument, :nifty_call_option, expiry_date: 1.month.from_now)

      expect(expired).to be_expired
      expect(expired).not_to be_currently_tradable
      expect(live_contract).to be_currently_tradable
    end
  end

  describe '.find_option (exact contract resolution)' do
    let(:underlying) { create(:instrument, :nifty_index, security_id: '13') }
    let!(:option) do
      create(:instrument, :nifty_call_option, underlying_symbol: 'NIFTY', security_id: '49081',
                                              expiry_date: Date.new(2026, 9, 24), strike_price: 25_000,
                                              underlying_instrument: underlying)
    end

    it 'resolves by underlying + expiry + strike + type in one query' do
      found = described_class.find_option(
        underlying_symbol: 'NIFTY',
        expiry_date: '2026-09-24',
        strike_price: 25_000,
        option_type: 'CE'
      )

      expect(found).to eq(option)
    end

    it 'resolves with BigDecimal / string strike inputs' do
      found = described_class.find_option(
        underlying_symbol: 'nifty',
        expiry_date: Date.new(2026, 9, 24),
        strike_price: BigDecimal('25000.00'),
        option_type: 'ce'
      )

      expect(found).to eq(option)
    end

    it 'returns nil for a non-existent contract' do
      expect(
        described_class.find_option(
          underlying_symbol: 'NIFTY',
          expiry_date: Date.new(2026, 9, 24),
          strike_price: 24_000,
          option_type: 'CE'
        )
      ).to be_nil
    end

    it 'is exposed through the legacy find_derivative_by_params alias' do
      expect(
        described_class.find_derivative_by_params(
          underlying_symbol: 'NIFTY', strike_price: 25_000,
          expiry_date: Date.new(2026, 9, 24), option_type: 'CE'
        )
      ).to eq(option)

      expect(
        described_class.find_security_id_by_params(
          underlying_symbol: 'NIFTY', strike_price: 25_000,
          expiry_date: Date.new(2026, 9, 24), option_type: 'CE'
        )
      ).to eq('49081')
    end
  end

  describe 'discovery scopes' do
    let(:underlying) { create(:instrument, :nifty_index, security_id: '13') }

    before do
      create(:instrument, :nifty_call_option, underlying_symbol: 'NIFTY', security_id: '49081',
                                              expiry_date: 1.week.from_now, strike_price: 25_000,
                                              underlying_instrument: underlying)
      create(:instrument, :nifty_put_option, underlying_symbol: 'NIFTY', security_id: '49082',
                                             expiry_date: 1.week.from_now, strike_price: 25_000,
                                             underlying_instrument: underlying)
      create(:instrument, :nifty_call_option, underlying_symbol: 'NIFTY', security_id: '49083',
                                              expiry_date: 2.weeks.from_now, strike_price: 25_100,
                                              underlying_instrument: underlying)
      create(:instrument, :nifty_future, underlying_symbol: 'NIFTY', security_id: '49084',
                                         strike_price: nil, option_type: nil,
                                         underlying_instrument: underlying)
    end

    it 'scopes options / ce / pe / futures / fno' do
      expect(described_class.options.where(underlying_symbol: 'NIFTY').count).to eq(3)
      expect(described_class.fno.count).to eq(4)
      expect(described_class.futures.where(underlying_symbol: 'NIFTY').count).to eq(1)
    end

    it 'lists distinct tradable expiries for an underlying' do
      expiries = described_class.option_expiries_for(underlying_symbol: 'NIFTY')

      expect(expiries.size).to eq(2)
      expect(expiries).to eq(expiries.sort) # nearest first
    end

    it 'returns options for one underlying + expiry, strike ordered' do
      options = described_class.options_for(underlying_symbol: 'NIFTY', expiry_date: 1.week.from_now.to_date)

      expect(options.map(&:option_type)).to eq(%w[CE PE])
    end
  end
end

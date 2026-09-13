# frozen_string_literal: true

require 'rails_helper'

# DEPRECATED model: Derivative is a read-only legacy facade over the frozen
# derivatives table. These specs pin the facade contract:
#
#   * lookups delegate to the consolidated Instrument master
#   * trading methods route through the consolidated Instrument so no new
#     Derivative-polymorphic records are created
#
# The behavioral specs for buying/selling options live in
# spec/models/instrument_buy_option_spec.rb.
RSpec.describe Derivative do
  let(:underlying) do
    Instrument.find_or_create_by!(security_id: '13') do |inst|
      inst.assign_attributes(
        symbol_name: 'NIFTY',
        exchange: 'nse',
        segment: 'index',
        instrument_type: 'INDEX',
        instrument_code: 'index'
      )
    end
  end
  let(:derivative) do
    create(:derivative, :nifty_call_option, instrument: underlying, security_id: '60001', lot_size: 25)
  end

  describe 'validations' do
    it 'validates option_type inclusion and scoped security_id uniqueness' do
      expect(build(:derivative, :nifty_call_option, instrument: underlying, security_id: '60001')).not_to be_valid
      expect(build(:derivative, instrument: underlying, security_id: '60010', option_type: 'XX')).not_to be_valid
    end
  end

  describe '#consolidated_instrument' do
    it 'finds the consolidated instrument by canonical broker identity' do
      consolidated = create(:instrument, :nifty_call_option, security_id: '60001', exchange: 'nse',
                                                             segment: 'derivatives', lot_size: 25,
                                                             underlying_instrument: underlying)

      expect(derivative.consolidated_instrument).to eq(consolidated)
    end

    it 'returns nil when no consolidated instrument exists' do
      expect(derivative.consolidated_instrument).to be_nil
    end
  end

  describe '#buy_option!' do
    it 'delegates to the consolidated instrument' do
      consolidated = instance_double(Instrument)
      allow(derivative).to receive(:consolidated_instrument).and_return(consolidated)

      expect(consolidated).to receive(:buy_option!).with(qty: 50, meta: { a: 1 })

      derivative.buy_option!(qty: 50, meta: { a: 1 })
    end

    it 'returns nil (and logs) when no consolidated instrument exists' do
      allow(Rails.logger).to receive(:error)

      expect(derivative.buy_option!(qty: 50)).to be_nil
      expect(Rails.logger).to have_received(:error).at_least(:once)
    end
  end

  describe '#sell_option!' do
    it 'delegates to the consolidated instrument' do
      consolidated = instance_double(Instrument)
      allow(derivative).to receive(:consolidated_instrument).and_return(consolidated)

      expect(consolidated).to receive(:sell_option!).with(qty: 25, meta: {})

      derivative.sell_option!(qty: 25)
    end
  end

  describe '.find_by_params (delegation)' do
    let!(:option) do
      create(:instrument, :nifty_call_option, underlying_symbol: 'NIFTY', security_id: '49081',
                                              expiry_date: Date.new(2026, 9, 24), strike_price: 25_000,
                                              underlying_instrument: underlying)
    end

    it 'resolves through the consolidated Instrument master' do
      expect(
        described_class.find_by_params(
          underlying_symbol: 'NIFTY', strike_price: 25_000,
          expiry_date: Date.new(2026, 9, 24), option_type: 'CE'
        )
      ).to eq(option)
    end

    it 'exposes find_security_id through the same path' do
      expect(
        described_class.find_security_id(
          underlying_symbol: 'NIFTY', strike_price: 25_000,
          expiry_date: Date.new(2026, 9, 24), option_type: 'CE'
        )
      ).to eq('49081')
    end
  end
end

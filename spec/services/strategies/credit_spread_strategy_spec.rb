# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::CreditSpreadStrategy do
  let(:short_leg) do
    {
      security_id: '1001',
      strike: 24_000,
      expiry_date: Date.current + 3.days
    }
  end

  let(:long_leg) do
    {
      security_id: '1002',
      strike: 23_900,
      expiry_date: Date.current + 3.days
    }
  end

  describe '#build_legs' do
    context 'for bull_put_spread' do
      subject(:strategy) do
        described_class.new(index_key: 'NIFTY', strategy_type: :bull_put_spread, quantity: 50)
      end

      it 'ensures buy hedge leg is leg_order 1 and short leg is leg_order 2' do
        legs = strategy.build_legs(short_leg_candidate: short_leg, long_leg_candidate: long_leg)

        expect(legs.size).to eq(2)
        expect(legs[0][:leg_order]).to eq(1)
        expect(legs[0][:action]).to eq('buy')
        expect(legs[0][:type]).to eq(:long_put)
        expect(legs[0][:security_id]).to eq('1002')

        expect(legs[1][:leg_order]).to eq(2)
        expect(legs[1][:action]).to eq('sell')
        expect(legs[1][:type]).to eq(:short_put)
        expect(legs[1][:security_id]).to eq('1001')
      end
    end

    context 'for bear_call_spread' do
      subject(:strategy) do
        described_class.new(index_key: 'NIFTY', strategy_type: :bear_call_spread, quantity: 50)
      end

      it 'ensures buy hedge leg is leg_order 1 and short leg is leg_order 2' do
        legs = strategy.build_legs(short_leg_candidate: short_leg, long_leg_candidate: long_leg)

        expect(legs.size).to eq(2)
        expect(legs[0][:leg_order]).to eq(1)
        expect(legs[0][:action]).to eq('buy')
        expect(legs[0][:type]).to eq(:long_call)

        expect(legs[1][:leg_order]).to eq(2)
        expect(legs[1][:action]).to eq('sell')
        expect(legs[1][:type]).to eq(:short_call)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LegGroup do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:group_id) }
    it { is_expected.to validate_presence_of(:strategy_type) }
    it { is_expected.to validate_presence_of(:underlying_symbol) }
    it { is_expected.to validate_presence_of(:expiry) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe '#create_from_executor_result!' do
    let(:instrument) { create(:instrument) }
    let(:result) do
      {
        group_id: 'ML_TEST123',
        legs: [
          { leg: { type: :long_put, action: 'buy' }, result: { fill_price: 15.0 }, coid: 'ML_TEST123_L1' },
          { leg: { type: :short_put, action: 'sell' }, result: { fill_price: 35.0 }, coid: 'ML_TEST123_L2' }
        ]
      }
    end

    it 'creates a leg group with active status and associates tracker attributes' do
      group = described_class.create_from_executor_result!(
        result,
        instrument: instrument,
        strategy_type: 'bull_put_spread',
        expiry: Date.current + 3.days,
        quantity: 50
      )

      expect(group).to be_persisted
      expect(group.group_id).to eq('ML_TEST123')
      expect(group.strategy_type).to eq('bull_put_spread')
      expect(group.status).to eq('active')
    end
  end
end

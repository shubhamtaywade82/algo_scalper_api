# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrderIntent do
  subject(:intent) { build(:order_intent) }

  describe 'validations' do
    it { is_expected.to belong_to(:instrument) }
    it { is_expected.to validate_presence_of(:strategy_name) }
    it { is_expected.to validate_presence_of(:side) }
    it { is_expected.to validate_inclusion_of(:side).in_array(described_class::SIDES) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).only_integer.is_greater_than(0) }
    it { is_expected.to validate_inclusion_of(:order_type).in_array(described_class::ORDER_TYPES) }
  end

  describe '#assign_correlation_id' do
    it 'auto-assigns correlation_id on create' do
      intent = create(:order_intent)
      expect(intent.correlation_id).to match(/\ATRD-\d{8}-\d{6}\z/)
    end

    it 'does not overwrite existing correlation_id' do
      intent = create(:order_intent, correlation_id: 'CUSTOM-001')
      expect(intent.correlation_id).to eq('CUSTOM-001')
    end
  end

  describe 'lifecycle methods' do
    let(:intent) { create(:order_intent) }

    it '#approve_risk! sets risk_approved and status' do
      intent.approve_risk!
      expect(intent).to be_risk_approved
      expect(intent.reload.status).to eq('risk_approved')
    end

    it '#approve_margin! sets margin_approved and status' do
      intent.submit_for_risk!
      intent.approve_risk!
      intent.approve_margin!
      expect(intent).to be_margin_approved
      expect(intent.reload.status).to eq('approved')
    end

    it '#reject! sets status and reason' do
      intent.reject!('max daily loss exceeded')
      expect(intent.reload.status).to eq('rejected')
      expect(intent.rejection_reason).to eq('max daily loss exceeded')
    end

    it '#terminal? returns true for terminal states' do
      intent.fill!
      expect(intent).to be_terminal
    end
  end

  describe 'scopes' do
    it '.today returns only today\'s intents' do
      create(:order_intent)
      expect(described_class.today.count).to eq(1)
    end
  end
end

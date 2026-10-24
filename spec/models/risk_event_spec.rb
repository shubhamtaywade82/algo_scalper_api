# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RiskEvent do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_inclusion_of(:severity).in_array(RiskEvent::SEVERITIES) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:instrument).optional }
    it { is_expected.to belong_to(:position_tracker).optional }
  end

  describe '#critical?' do
    it 'returns true if severity is critical' do
      event = build(:risk_event, severity: 'critical')
      expect(event.critical?).to be true
    end

    it 'returns false if severity is not critical' do
      event = build(:risk_event, severity: 'warning')
      expect(event.critical?).to be false
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RiskEvent, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:source) }
    it { should validate_inclusion_of(:severity).in_array(RiskEvent::SEVERITIES) }
  end

  describe 'associations' do
    it { should belong_to(:instrument).optional }
    it { should belong_to(:position_tracker).optional }
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

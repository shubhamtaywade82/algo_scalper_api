# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  it 'requires event_type' do
    log = described_class.new(metadata: {})

    expect(log).not_to be_valid
    expect(log.errors[:event_type]).to be_present
  end

  it 'persists arbitrary metadata as jsonb' do
    log = described_class.create!(event_type: 'kill_switch_trip', actor: 'system', metadata: { reason: 'test' })

    expect(log.reload.metadata).to eq('reason' => 'test')
  end

  it 'defaults metadata to an empty hash rather than nil' do
    log = described_class.create!(event_type: 'bot_start')

    expect(log.metadata).to eq({})
  end

  describe '.recent_first' do
    it 'orders by created_at descending' do
      older = described_class.create!(event_type: 'bot_start', created_at: 2.days.ago)
      newer = described_class.create!(event_type: 'bot_stop', created_at: 1.day.ago)

      expect(described_class.recent_first.to_a).to eq([newer, older])
    end
  end
end

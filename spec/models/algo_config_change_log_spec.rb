# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfigChangeLog do
  describe 'validations' do
    it 'requires source' do
      record = described_class.new(patch: { x: 1 }, metadata: {})
      expect(record).not_to be_valid
      expect(record.errors[:source]).to be_present
    end

    it 'persists with valid attributes' do
      record = described_class.create!(
        source: 'test',
        actor: 'rspec',
        patch: { key: 'value' },
        changed_paths: ['/risk'],
        metadata: {}
      )
      expect(record).to be_persisted
      expect(record.patch).to eq('key' => 'value')
    end
  end

  describe '.recent_first' do
    it 'orders by created_at descending' do
      old = described_class.create!(source: 'a', patch: {}, metadata: {}, created_at: 1.hour.ago)
      new_rec = described_class.create!(source: 'b', patch: {}, metadata: {})

      expect(described_class.recent_first.first).to eq(new_rec)
      expect(described_class.recent_first.last).to eq(old)
    end
  end

  describe 'changed_paths array column' do
    it 'stores and retrieves string arrays' do
      record = described_class.create!(
        source: 'test',
        patch: {},
        changed_paths: ['/risk', '/signals'],
        metadata: {}
      )
      expect(record.reload.changed_paths).to eq(['/risk', '/signals'])
    end

    it 'defaults to empty array' do
      record = described_class.create!(source: 'test', patch: {}, metadata: {})
      expect(record.reload.changed_paths).to eq([])
    end
  end
end

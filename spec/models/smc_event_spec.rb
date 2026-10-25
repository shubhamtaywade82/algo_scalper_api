# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmcEvent do
  describe 'validations' do
    it 'is invalid without stream, event_type, correlation_id, or payload' do
      event = described_class.new
      expect(event).not_to be_valid
      expect(event.errors[:stream]).to be_present
      expect(event.errors[:event_type]).to be_present
      expect(event.errors[:correlation_id]).to be_present
      expect(event.errors[:payload]).to be_present
    end

    it 'is valid with all required attributes' do
      event = described_class.new(
        stream: 'NIFTY',
        event_type: 'structure_break',
        correlation_id: 'corr-1',
        payload: { swing: 'high' }
      )
      expect(event).to be_valid
    end
  end

  describe 'sequence auto-assignment' do
    it 'assigns sequence 1 to the first event of a correlation' do
      event = described_class.create!(
        stream: 'NIFTY', event_type: 'bos', correlation_id: 'corr-first', payload: { v: 1 }
      )
      expect(event.sequence).to eq(1)
    end

    it 'increments sequence per correlation_id' do
      described_class.create!(stream: 'NIFTY', event_type: 'bos', correlation_id: 'corr-seq', payload: { v: 1 })
      second = described_class.create!(stream: 'NIFTY', event_type: 'choch', correlation_id: 'corr-seq', payload: { v: 1 })

      expect(second.sequence).to eq(2)
    end

    it 'keeps sequences independent between correlations' do
      described_class.create!(stream: 'NIFTY', event_type: 'bos', correlation_id: 'corr-a', payload: { v: 1 })
      other = described_class.create!(stream: 'NIFTY', event_type: 'bos', correlation_id: 'corr-b', payload: { v: 1 })

      expect(other.sequence).to eq(1)
    end

    it 'preserves an explicitly provided sequence' do
      event = described_class.new(
        stream: 'NIFTY', event_type: 'bos', correlation_id: 'corr-explicit', payload: { swing: 'low' }, sequence: 42
      )
      event.validate!
      expect(event.sequence).to eq(42)
    end
  end
end

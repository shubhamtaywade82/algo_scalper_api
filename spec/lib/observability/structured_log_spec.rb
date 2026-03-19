# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Observability::StructuredLog do
  describe '.info' do
    it 'emits json payload with event and fields' do
      allow(Rails.logger).to receive(:info)

      described_class.info(
        event: 'entry_order_placed',
        payload: { service: 'Entries::EntryGuard' }
      )

      expect(Rails.logger).to have_received(:info) do |message|
        payload = JSON.parse(message)
        expect(payload['event']).to eq('entry_order_placed')
        expect(payload['service']).to eq('Entries::EntryGuard')
        expect(payload['timestamp']).to be_present
      end
    end
  end
end

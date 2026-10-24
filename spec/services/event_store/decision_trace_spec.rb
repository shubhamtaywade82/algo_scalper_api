# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventStore::DecisionTrace do
  describe '.with_trace' do
    it 'creates a unique decision_id and binds it to the current thread' do
      described_class.with_trace(index_key: :nifty, direction: :bullish) do |trace|
        expect(trace.decision_id).to be_present
        expect(trace.index_key).to eq(:nifty)
        expect(described_class.current_id).to eq(trace.decision_id)
      end
      expect(described_class.current_id).to be_nil
    end

    it 'allows marking trace status' do
      described_class.with_trace(index_key: :banknifty, direction: :bearish) do |trace|
        expect(trace.status).to eq(:initiated)
        trace.mark_status(:approved)
        expect(trace.status).to eq(:approved)
      end
    end
  end
end

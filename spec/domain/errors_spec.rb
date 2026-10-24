# frozen_string_literal: true

require 'rails_helper'

# Contract smoke test for the domain error taxonomy (error-handling review
# 2026-09). Every typed failure state the trading paths raise lives here so
# downstream rescue/branching stays precise.
RSpec.describe Errors do
  it 'roots every domain error in Errors::Error' do
    [
      Errors::ConfigurationError, Errors::InvalidInstrument, Errors::InstrumentNotFound,
      Errors::InvalidMarketData, Errors::StaleMarketData, Errors::InvalidQuantity,
      Errors::InvalidPrice, Errors::RiskViolation, Errors::ExecutionRejected,
      Errors::LedgerFailure, Errors::InvariantViolation, Errors::InvalidParameter
    ].each do |klass|
      expect(klass.ancestors).to include(Errors::Error, StandardError)
    end
  end

  describe Errors::InstrumentNotFound do
    it 'carries the query for actionable logs' do
      query = { security_id: '49081', segment: 'NSE_FNO' }
      error = described_class.new(query, 'nope')

      expect(error.query).to eq(query)
      expect(error.message).to eq('nope')
    end

    it 'derives a message from the query when none is given' do
      error = described_class.new({ security_id: '49081' })

      expect(error.message).to include('49081')
    end
  end
end

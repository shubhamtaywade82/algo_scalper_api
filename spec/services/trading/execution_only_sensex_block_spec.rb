# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Execution-only blocked for SENSEX' do
  it 'results in 0 lots for SENSEX in execution_only' do
    profile = Trading::InstrumentExecutionProfile.for('SENSEX')
    permission_cap = profile[:max_lots_by_permission][:execution_only]

    lots = Trading::CapitalAllocator.max_lots(
      premium: 100,
      lot_size: Trading::LotCalculator.lot_size_for('SENSEX'),
      permission_cap: permission_cap
    )

    expect(profile[:allow_execution_only]).to be(false)
    expect(permission_cap).to eq(0)
    expect(lots).to eq(0)
  end
end

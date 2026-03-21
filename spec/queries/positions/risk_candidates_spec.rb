# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::RiskCandidates do
  describe '.call' do
    it 'returns active positions below the max loss threshold' do
      risky_tracker = create(:position_tracker, status: 'active', segment: 'NSE_FNO', last_pnl_rupees: -1500.0)
      create(:position_tracker, status: 'active', segment: 'NSE_FNO', last_pnl_rupees: -500.0)
      create(:position_tracker, :exited, segment: 'NSE_FNO', last_pnl_rupees: -5000.0)

      trackers = described_class.call(max_loss: 1000)

      expect(trackers).to contain_exactly(risky_tracker)
    end
  end
end

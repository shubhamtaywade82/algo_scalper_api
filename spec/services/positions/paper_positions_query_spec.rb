# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::PaperPositionsQuery do
  describe '.call' do
    it 'returns paginated serialized paper positions' do
      create(:position_tracker, :paper, segment: 'NSE_FNO', status: 'active')
      create(:position_tracker, :paper, :exited, segment: 'NSE_FNO')
      create(:position_tracker, segment: 'NSE_FNO', status: 'active', paper: false)

      result = described_class.call(limit: 1, offset: 0)

      expect(result.size).to eq(1)
      expect(result.first).to include(:id, :status, :unrealized)
      expect(result.first).not_to have_key(:unrealized?)
    end
  end
end

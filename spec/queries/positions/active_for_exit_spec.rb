# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ActiveForExit do
  describe '.call' do
    it 'returns only active positions' do
      active_tracker = create(:position_tracker, status: 'active', segment: 'NSE_FNO')
      create(:position_tracker, :exited, segment: 'NSE_FNO')

      trackers = described_class.call

      expect(trackers).to include(active_tracker)
      expect(trackers.pluck(:status).uniq).to eq(['active'])
    end
  end
end

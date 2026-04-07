# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::MomentumValidator do
  describe '.validate_option_pick' do
    it 'confirms bullish option premium acceleration when premium is above previous close' do
      result = described_class.validate_option_pick(
        index_key: 'NIFTY',
        pick: { ltp: 118.0, prev_close: 100.0 },
        direction: :bullish
      )

      expect(result[:confirms]).to be true
      expect(result[:reason]).to include('Option premium speed')
    end

    it 'confirms bearish option premium acceleration for a PE premium expansion' do
      result = described_class.validate_option_pick(
        index_key: 'SENSEX',
        pick: { ltp: 109.0, prev_close: 100.0 },
        direction: :bearish
      )

      expect(result[:confirms]).to be true
    end

    it 'rejects when previous close is unavailable' do
      result = described_class.validate_option_pick(
        index_key: 'NIFTY',
        pick: { ltp: 118.0, prev_close: 0.0 },
        direction: :bullish
      )

      expect(result[:confirms]).to be false
      expect(result[:reason]).to eq('Previous option close unavailable')
    end

    it 'rejects when premium expansion is below threshold' do
      result = described_class.validate_option_pick(
        index_key: 'NIFTY',
        pick: { ltp: 103.0, prev_close: 100.0 },
        direction: :bullish
      )

      expect(result[:confirms]).to be false
      expect(result[:reason]).to include('< 8.0% threshold')
    end
  end
end

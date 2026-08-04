# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeQualification::ExpectedMoveValidator do
  subject(:validator) { described_class.new }

  describe '#call' do
    it 'blocks NIFTY when expected premium is too low' do
      result = validator.call(
        index_key: 'NIFTY',
        strike_type: :ATM,
        permission: :execution_only,
        expected_spot_move: 5.0,
        option_ltp: 120.0
      )

      expect(result[:ok]).to eq(false)
      expect(result[:reason]).to eq('expected_premium_below_threshold')
    end

    it 'allows NIFTY when expected premium meets threshold' do
      result = validator.call(
        index_key: 'NIFTY',
        strike_type: :ATM,
        permission: :execution_only,
        expected_spot_move: 10.0,
        option_ltp: 120.0
      )

      expect(result[:ok]).to eq(true)
      expect(result[:expected_premium]).to be >= result[:threshold]
    end

    it 'blocks NIFTY full_deploy for ATM±1 when expectancy is insufficient' do
      result = validator.call(
        index_key: 'NIFTY',
        strike_type: :ATM_PLUS_1,
        permission: :full_deploy,
        expected_spot_move: 20.0,
        option_ltp: 120.0
      )

      # 20 * 0.40 = 8 < 12
      expect(result[:ok]).to eq(false)
      expect(result[:reason]).to eq('expected_premium_below_threshold')
    end

    it 'always blocks SENSEX execution_only' do
      result = validator.call(
        index_key: 'SENSEX',
        strike_type: :ATM,
        permission: :execution_only,
        expected_spot_move: 50.0,
        option_ltp: 200.0
      )

      expect(result[:ok]).to eq(false)
      expect(result[:reason]).to eq('sensex_execution_only_blocked')
    end
  end
end


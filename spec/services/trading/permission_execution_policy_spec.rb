# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::PermissionExecutionPolicy do
  describe '.for' do
    it 'returns blocked policy' do
      expected = {
        max_lots: 0,
        allow_scaling: false,
        max_scale_steps: 0,
        profit_targets: [],
        hard_stop_pct: 0.0,
        time_stop_candles: 0,
        allow_runner: false
      }

      policy = described_class.for(permission: :blocked)
      expect(policy).to eq(expected)

      # Unknown permission defaults to blocked
      expect(described_class.for(permission: :unknown)).to eq(expected)

      # Ensure no mutation of returned hashes/arrays
      expect { policy[:max_lots] = 99 }.to raise_error(FrozenError)
      expect { policy[:profit_targets] << 999 }.to raise_error(FrozenError)
    end

    it 'returns execution_only policy' do
      expected = {
        max_lots: 1,
        allow_scaling: false,
        max_scale_steps: 0,
        profit_targets: [4, 6],
        hard_stop_pct: 0.20,
        time_stop_candles: 2,
        allow_runner: false
      }

      policy = described_class.for(permission: :execution_only)
      expect(policy).to eq(expected)

      expect { policy[:profit_targets] << 999 }.to raise_error(FrozenError)
    end

    it 'returns scale_ready policy' do
      expected = {
        max_lots: 2,
        allow_scaling: true,
        max_scale_steps: 1,
        profit_targets: [6, 10],
        hard_stop_pct: 0.22,
        time_stop_candles: 3,
        allow_runner: false
      }

      policy = described_class.for(permission: :scale_ready)
      expect(policy).to eq(expected)

      expect { policy[:profit_targets] << 999 }.to raise_error(FrozenError)
    end

    it 'returns full_deploy policy' do
      expected = {
        max_lots: 4,
        allow_scaling: true,
        max_scale_steps: 3,
        profit_targets: [6, 10, 15],
        hard_stop_pct: 0.25,
        time_stop_candles: 3,
        allow_runner: true
      }

      policy = described_class.for(permission: :full_deploy)
      expect(policy).to eq(expected)

      expect { policy[:profit_targets] << 999 }.to raise_error(FrozenError)
    end
  end
end

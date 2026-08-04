# frozen_string_literal: true

require 'rails_helper'

# Explicitly require the class file to ensure it's loaded
require_relative '../../../app/services/trading/atr_permission_modifier'

RSpec.describe Trading::AtrPermissionModifier do
  describe '.apply' do
    context 'when atr_current below median' do
      it 'downgrades full_deploy to scale_ready' do
        result = described_class.apply(
          permission: :full_deploy,
          atr_current: 90.0,
          atr_session_median: 100.0,
          atr_slope: 1.0
        )

        expect(result).to eq(:scale_ready)
      end

      it 'downgrades scale_ready to execution_only' do
        result = described_class.apply(
          permission: :scale_ready,
          atr_current: 90.0,
          atr_session_median: 100.0,
          atr_slope: 1.0
        )

        expect(result).to eq(:execution_only)
      end
    end

    context 'when atr_slope non-positive' do
      it 'downgrades full_deploy to scale_ready' do
        result = described_class.apply(
          permission: :full_deploy,
          atr_current: 120.0,
          atr_session_median: 100.0,
          atr_slope: 0.0
        )

        expect(result).to eq(:scale_ready)
      end
    end

    context 'when atr is strong' do
      it 'never upgrades and is idempotent' do
        first = described_class.apply(
          permission: :execution_only,
          atr_current: 120.0,
          atr_session_median: 100.0,
          atr_slope: 1.0
        )
        second = described_class.apply(
          permission: first,
          atr_current: 120.0,
          atr_session_median: 100.0,
          atr_slope: 1.0
        )

        expect(first).to eq(:execution_only)
        expect(second).to eq(:execution_only)
      end
    end
  end
end

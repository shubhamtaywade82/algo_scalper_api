# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::SmcPermissionResolver do
  describe '.resolve' do
    it 'returns :blocked when structure is neutral' do
      smc = {
        structure_state: :neutral,
        bos_recent: false,
        displacement: false,
        trend: :neutral
      }
      avrz = { state: :compressed }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:blocked)
    end

    it 'returns :execution_only' do
      smc = {
        structure_state: :trend,
        bos_recent: true,
        displacement: false,
        liquidity_event_resolved: false,
        trend: :bullish
      }
      avrz = { state: :compressed }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:execution_only)
    end

    it 'returns :scale_ready' do
      smc = {
        structure_state: :trend,
        bos_recent: true,
        displacement: true,
        active_liquidity_trap: false,
        trap_resolved: false,
        follow_through: false,
        trend: :bullish
      }
      avrz = { state: :expanding_early }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:scale_ready)
    end

    it 'returns :full_deploy' do
      smc = {
        structure_state: :trend,
        bos_recent: true,
        displacement: true,
        follow_through: true,
        trap_resolved: false,
        trend: :bullish
      }
      avrz = { state: :expanding }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:full_deploy)
    end
  end
end

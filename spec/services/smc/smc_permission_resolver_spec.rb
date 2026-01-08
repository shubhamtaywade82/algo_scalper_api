# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::SmcPermissionResolver do
  describe '.resolve' do
    it 'returns :blocked' do
      smc = {
        structure_state: :range,
        bos_recent: true,
        displacement: true,
        liquidity_event_resolved: true,
        active_liquidity_trap: false,
        trap_resolved: true,
        follow_through: true,
        trend: :bullish
      }
      avrz = { state: :compressed }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:blocked)
    end

    it 'returns :execution_only' do
      smc = {
        structure_state: :bullish,
        bos_recent: true,
        displacement: false, # no displacement -> execution only (no scaling)
        liquidity_event_resolved: false,
        trend: :bullish
      }
      avrz = { state: :compressed }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:execution_only)
    end

    it 'returns :scale_ready' do
      smc = {
        structure_state: :bullish,
        bos_recent: true,
        displacement: true,
        active_liquidity_trap: false, # must be explicitly false
        trap_resolved: false,
        follow_through: false,
        trend: :bullish
      }
      avrz = { state: :expanding_early }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:scale_ready)
    end

    it 'returns :full_deploy' do
      smc = {
        structure_state: :bullish,
        bos_recent: true,
        displacement: true,
        follow_through: true, # clean BOS + follow-through
        trap_resolved: false,
        trend: :bullish
      }
      avrz = { state: :expanding }

      expect(described_class.resolve(smc_result: smc, avrz_result: avrz)).to eq(:full_deploy)
    end
  end
end


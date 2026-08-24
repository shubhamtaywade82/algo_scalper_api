# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::AgentSupervisor do
  subject(:supervisor) { described_class.instance }

  describe '#authority_level' do
    it 'is always :advisor in this phase, for every agent name' do
      described_class::AGENT_NAMES.each do |name|
        expect(supervisor.authority_level(name)).to eq(:advisor)
      end
      expect(supervisor.authority_level('anything_else')).to eq(:advisor)
    end
  end

  describe '#capability_granted?' do
    it 'grants only read-only/advisory capabilities' do
      expect(supervisor.capability_granted?('market_analysis_agent', :read_market)).to be true
      expect(supervisor.capability_granted?('market_analysis_agent', :suggest_strategy)).to be true
    end

    it 'never grants an order-placing capability' do
      expect(supervisor.capability_granted?('execution_agent', :place_order)).to be false
    end
  end

  describe '#capability_forbidden?' do
    it 'flags every trading-authority capability as forbidden' do
      %i[place_order cancel_order modify_order modify_risk_limit trip_circuit_breaker apply_config].each do |cap|
        expect(supervisor.capability_forbidden?(cap)).to be true
      end
    end
  end

  describe '#status' do
    it 'reports a status row for every known agent' do
      AgentDecisionLog.create!(agent_name: 'market_analysis_agent', decision_type: 'market_state')

      status = supervisor.status
      expect(status.keys).to match_array(described_class::AGENT_NAMES)
      expect(status['market_analysis_agent'][:decisions_today]).to eq(1)
    end
  end
end

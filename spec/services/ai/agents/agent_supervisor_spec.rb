# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::AgentSupervisor do
  subject(:supervisor) { described_class.instance }

  describe '#authority_level' do
    it 'is :level_2 only for dynamic_config_agent' do
      expect(supervisor.authority_level('dynamic_config_agent')).to eq(:level_2)
    end

    it 'is :advisor for every other known agent name, and for unknown names' do
      (described_class::AGENT_NAMES - ['dynamic_config_agent']).each do |name|
        expect(supervisor.authority_level(name)).to eq(:advisor)
      end
      expect(supervisor.authority_level('anything_else')).to eq(:advisor)
    end
  end

  describe '#capability_granted?' do
    it 'grants only read-only/advisory capabilities to advisor agents' do
      expect(supervisor.capability_granted?('market_analysis_agent', :read_market)).to be true
      expect(supervisor.capability_granted?('market_analysis_agent', :suggest_strategy)).to be true
    end

    it 'never grants an order-placing capability to any agent' do
      expect(supervisor.capability_granted?('execution_agent', :place_order)).to be false
      expect(supervisor.capability_granted?('dynamic_config_agent', :place_order)).to be false
    end

    it 'grants apply_config only to dynamic_config_agent' do
      expect(supervisor.capability_granted?('dynamic_config_agent', :apply_config)).to be true
      expect(supervisor.capability_granted?('market_analysis_agent', :apply_config)).to be false
      expect(supervisor.capability_granted?('calibration_agent', :apply_config)).to be false
    end
  end

  describe '#capability_forbidden?' do
    it 'flags every order-execution/risk-override capability as forbidden' do
      %i[place_order cancel_order modify_order modify_risk_limit trip_circuit_breaker].each do |cap|
        expect(supervisor.capability_forbidden?(cap)).to be true
      end
    end

    it 'does not blanket-forbid apply_config, since one agent is granted it' do
      expect(supervisor.capability_forbidden?(:apply_config)).to be false
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

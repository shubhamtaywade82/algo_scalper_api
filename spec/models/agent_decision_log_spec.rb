# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentDecisionLog do
  it 'requires agent_name and decision_type' do
    log = described_class.new
    expect(log).not_to be_valid
    expect(log.errors.attribute_names).to include(:agent_name, :decision_type)
  end

  it 'requires authority_level when explicitly blanked out' do
    log = described_class.new(agent_name: 'a', decision_type: 'x', authority_level: nil)
    expect(log).not_to be_valid
    expect(log.errors.attribute_names).to include(:authority_level)
  end

  it 'defaults authority_level to advisor at the DB level' do
    log = described_class.create!(agent_name: 'test_agent', decision_type: 'noop')
    expect(log.authority_level).to eq('advisor')
  end

  describe '.for_agent' do
    it 'scopes to the given agent name' do
      described_class.create!(agent_name: 'agent_a', decision_type: 'x')
      described_class.create!(agent_name: 'agent_b', decision_type: 'x')

      expect(described_class.for_agent('agent_a').pluck(:agent_name)).to eq(['agent_a'])
    end
  end

  describe '#failed?' do
    it 'is true when an error is recorded' do
      log = described_class.create!(agent_name: 'a', decision_type: 'x', error: 'boom')
      expect(log).to be_failed
    end

    it 'is false otherwise' do
      log = described_class.create!(agent_name: 'a', decision_type: 'x')
      expect(log).not_to be_failed
    end
  end
end

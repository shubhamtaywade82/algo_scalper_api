# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ExecutionAgent do
  subject(:agent) { described_class.new }

  it 'reports zero confidence when no tracker has FSM history' do
    create(:position_tracker, meta: {})

    result = agent.run
    expect(result[:output][:sample_size]).to eq(0)
    expect(result[:confidence]).to eq(0.0)
  end

  it 'computes fill latency from meta[fsm_history] transitions' do
    t0 = Time.current
    create(:position_tracker, meta: {
             'fsm_history' => [
               { 'to_state' => 'submitting', 'transitioned_at' => t0.iso8601(3) },
               { 'to_state' => 'filled', 'transitioned_at' => (t0 + 2.5).iso8601(3) }
             ]
           })

    result = agent.run
    expect(result[:output][:sample_size]).to eq(1)
    expect(result[:output][:avg_fill_latency_seconds]).to be_within(0.01).of(2.5)
  end

  it 'ignores trackers with incomplete FSM history without raising' do
    create(:position_tracker, meta: { 'fsm_history' => [{ 'to_state' => 'submitting', 'transitioned_at' => Time.current.iso8601(3) }] })

    expect { agent.run }.not_to raise_error
  end
end

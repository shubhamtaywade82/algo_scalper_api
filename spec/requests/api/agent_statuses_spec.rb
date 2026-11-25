# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::AgentStatuses' do
  let(:snapshot) do
    JSON.parse(Rails.root.join('contracts/fixtures/agent-snapshot-1.example.json').read)
        .merge('updated_at' => 2.seconds.ago.iso8601(3))
  end

  it 'reports the agent online with its snapshot and recent intent outcomes' do
    allow(TradeIntents::AgentSnapshot).to receive(:read).and_return(snapshot)
    TradeIntent.create!(intent_id: SecureRandom.uuid, mode: 'paper', underlying: 'NIFTY', direction: 'BEARISH',
                        source_strategy: 'signal-engine', confidence: 0.5, payload: {}, expires_at: 1.minute.ago,
                        outcome: 'dropped', outcome_code: 'SLOT_BUSY')

    get '/api/agent/status'

    body = response.parsed_body
    expect(body).to include('online' => true, 'snapshot' => snapshot)
    expect(body['age_ms']).to be_between(1_000, 5_000)
    expect(body['recent_intents'].first).to include('underlying' => 'NIFTY', 'outcome' => 'dropped', 'code' => 'SLOT_BUSY')
  end

  it 'reports offline when the agent is not publishing' do
    allow(TradeIntents::AgentSnapshot).to receive(:read).and_return(nil)

    get '/api/agent/status'

    expect(response.parsed_body).to include('online' => false, 'snapshot' => nil, 'engine' => 'rails')
  end

  it 'reports offline when the snapshot is stale' do
    allow(TradeIntents::AgentSnapshot).to receive(:read).and_return(snapshot.merge('updated_at' => 30.seconds.ago.iso8601))

    get '/api/agent/status'

    expect(response.parsed_body['online']).to be(false)
  end
end

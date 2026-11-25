# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::TradeIntents' do
  let(:operator_token) { 'operator-secret' }
  let(:headers) { { 'Authorization' => "Bearer #{operator_token}", 'Content-Type' => 'application/json' } }

  around do |example|
    prior = ENV.fetch('API_OPERATOR_TOKEN', nil)
    ENV['API_OPERATOR_TOKEN'] = operator_token
    example.run
  ensure
    prior ? ENV['API_OPERATOR_TOKEN'] = prior : ENV.delete('API_OPERATOR_TOKEN')
  end

  def create_intent(expires_at: 15.seconds.from_now, **attrs)
    intent_id = SecureRandom.uuid
    payload = JSON.parse(Rails.root.join('contracts/fixtures/trade-intent-1.example.json').read)
                  .merge('intent_id' => intent_id, 'expires_at' => expires_at.iso8601(3))
    TradeIntent.create!({ intent_id: intent_id, mode: 'paper', underlying: 'NIFTY', direction: 'BULLISH',
                          source_strategy: 'supertrend-adx', confidence: 0.7, payload: payload,
                          expires_at: expires_at }.merge(attrs))
  end

  describe 'GET /api/trade_intents' do
    before do
      allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
      allow(TradeIntents::Forwarder).to receive(:agent_engine?).and_return(true)
    end

    it 'returns pending intents after the cursor in a trade-intents/1 envelope' do
      seen = create_intent
      fresh = create_intent(underlying: 'SENSEX')
      create_intent(expires_at: 1.second.ago)
      create_intent(outcome: 'accepted')

      get '/api/trade_intents', params: { after: seen.id.to_s, mode: 'paper' }, headers: headers

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(Contracts::Schema.errors('trade-intents-1', body)).to be_empty
      expect(body['intents'].pluck('intent_id')).to eq([fresh.intent_id])
      expect(body['cursor']).to eq(fresh.id.to_s)
      expect(body['control']).to include('intake_enabled' => true, 'circuit_breaker' => { 'tripped' => false })
      body['intents'].each { |intent| expect(Contracts::Schema.errors('trade-intent-1', intent)).to be_empty }
    end

    it 'echoes the cursor when nothing is pending' do
      get '/api/trade_intents', params: { after: '77' }, headers: headers

      expect(response.parsed_body).to include('cursor' => '77', 'intents' => [])
    end

    it 'requires the operator token' do
      get '/api/trade_intents'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/trade_intents/:intent_id/outcome' do
    let(:intent) { create_intent }
    let(:outcome) do
      JSON.parse(Rails.root.join('contracts/fixtures/intent-outcome-1.example.json').read).merge('intent_id' => intent.intent_id)
    end

    def post_outcome(body)
      post "/api/trade_intents/#{intent.intent_id}/outcome", params: body.to_json, headers: headers
    end

    it 'records the first outcome and ignores repeats' do
      post_outcome(outcome)
      expect(response.parsed_body).to eq('status' => 'recorded')
      expect(intent.reload).to have_attributes(outcome: outcome['outcome'], correlation_id: outcome['correlation_id'])

      post_outcome(outcome.merge('outcome' => 'accepted'))
      expect(response.parsed_body).to eq('status' => 'already_recorded')
      expect(intent.reload.outcome).to eq(outcome['outcome'])
    end

    it 'rejects a payload that breaks the intent-outcome/1 contract' do
      post_outcome(outcome.except('correlation_id'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(intent.reload.outcome).to be_nil
    end

    it 'rejects an outcome for a different intent' do
      post_outcome(outcome.merge('intent_id' => SecureRandom.uuid))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns not found for an unknown intent' do
      post "/api/trade_intents/#{SecureRandom.uuid}/outcome", params: outcome.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

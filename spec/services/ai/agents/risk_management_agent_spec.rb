# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::RiskManagementAgent do
  subject(:agent) { described_class.new }

  before do
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: false, reason: nil, at: nil })
  end

  it 'reports :normal risk when the circuit breaker is not tripped and no losses today' do
    result = agent.run
    expect(result[:output][:risk_level]).to eq(:normal)
    expect(result[:published_event]).to be_nil
  end

  it 'reports :critical and publishes a risk_alert when the circuit breaker is tripped' do
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: true, reason: 'test', at: Time.current })

    result = agent.run
    expect(result[:output][:risk_level]).to eq(:critical)
    expect(result[:published_event]).to eq('risk_alert')
  end

  it 'reports :elevated after 2+ consecutive losing exits today' do
    create(:position_tracker, :exited, exited_at: 1.hour.ago, last_pnl_rupees: -100)
    create(:position_tracker, :exited, exited_at: 30.minutes.ago, last_pnl_rupees: -200)

    result = agent.run
    expect(result[:output][:risk_level]).to eq(:elevated)
  end

  it 'never itself trips the circuit breaker or force-closes positions' do
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: true, reason: 'x', at: Time.current })
    allow(Risk::CircuitBreaker.instance).to receive(:trip!)
    allow(Risk::CircuitBreaker.instance).to receive(:force_close_all!)

    agent.run

    expect(Risk::CircuitBreaker.instance).not_to have_received(:trip!)
    expect(Risk::CircuitBreaker.instance).not_to have_received(:force_close_all!)
  end
end

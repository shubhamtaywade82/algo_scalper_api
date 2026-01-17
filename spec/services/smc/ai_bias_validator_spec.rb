# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::AiBiasValidator do
  subject(:result) { described_class.call(initial_data: initial_data) }

  let(:initial_data) do
    {
      decision: :call,
      timeframes: {
        htf: { interval: '60', context: {} },
        mtf: { interval: '15', context: {} },
        ltf: { interval: '5', context: {} }
      }
    }
  end
  let(:client) do
    instance_double(Services::Ai::OpenaiClient, enabled?: true, provider: :ollama, selected_model: 'llama3.2:3b')
  end

  before do
    allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    allow(AlgoConfig).to receive(:fetch).and_return(ai: { enabled: true })
  end

  context 'when response matches schema' do
    let(:payload) do
      {
        'market_bias' => 'bullish',
        'market_regime' => 'trending',
        'directional_allowance' => 'CE_ONLY',
        'decision_alignment' => 'ALIGNED',
        'decision_valid' => true,
        'confidence' => 82,
        'suggested_duration' => '15m',
        'explanation' => 'HTF and MTF bullish with LTF confirmation'
      }
    end

    before do
      allow(client).to receive(:chat).and_return(content: JSON.generate(payload))
    end

    it 'returns normalized JSON' do
      expect(JSON.parse(result)).to eq(payload)
    end
  end

  context 'when response is invalid JSON' do
    before do
      allow(client).to receive(:chat).and_return(content: 'not-json')
    end

    it 'returns nil' do
      expect(result).to be_nil
    end
  end

  context 'when AI is disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(ai: { enabled: false })
      allow(client).to receive(:chat)
    end

    it 'returns nil' do
      expect(result).to be_nil
    end

    it 'does not call the client' do
      result

      expect(client).not_to have_received(:chat)
    end
  end
end

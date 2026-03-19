# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AiSnapshotPromptBuilder do
  let(:full_params) do
    {
      index_key: 'NIFTY',
      ltp: 22_450.0,
      smc: { 'trend' => 'bullish', 'structure' => 'BOS confirmed' },
      regime: { 'label' => 'trending', 'strength' => 0.8 },
      calibration_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 }
    }
  end

  describe '.build' do
    subject(:messages) { described_class.build(**full_params) }

    it 'returns an array of message hashes' do
      expect(messages).to be_an(Array)
      expect(messages).not_to be_empty
    end

    it 'each message has :role and :content keys' do
      expect(messages).to all(
        satisfy { |msg| msg.key?(:role) && msg.key?(:content) }
      )
    end

    it 'includes a system message' do
      roles = messages.pluck(:role)
      expect(roles).to include('system')
    end

    it 'includes a user message with index_key' do
      user_msg = messages.find { |m| m[:role] == 'user' }
      expect(user_msg).not_to be_nil
      expect(user_msg[:content]).to include('NIFTY')
    end

    it 'includes LTP in the user prompt' do
      user_msg = messages.find { |m| m[:role] == 'user' }
      expect(user_msg[:content]).to include('22450')
    end

    context 'with all params nil' do
      it 'still returns valid message array without raising' do
        messages = described_class.build(
          index_key: 'NIFTY', ltp: nil, smc: nil, regime: nil, calibration_stats: nil
        )
        expect(messages).to be_an(Array)
        expect(messages.size).to be >= 1
      end
    end

    context 'with only index_key provided' do
      it 'builds a minimal but valid prompt' do
        messages = described_class.build(
          index_key: 'SENSEX', ltp: nil, smc: nil, regime: nil, calibration_stats: nil
        )
        user_msg = messages.find { |m| m[:role] == 'user' }
        expect(user_msg[:content]).to include('SENSEX')
      end
    end
  end
end

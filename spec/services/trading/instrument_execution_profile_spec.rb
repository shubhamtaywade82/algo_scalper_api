# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::InstrumentExecutionProfile do
  describe '.for' do
    context 'when symbol is NIFTY' do
      it 'returns the expected profile' do
        profile = described_class.for('NIFTY')

        expect(profile[:allow_execution_only]).to eq(true)
        expect(profile[:max_lots_by_permission]).to eq(
          execution_only: 1,
          scale_ready: 2,
          full_deploy: 4
        )
        expect(profile[:target_model]).to eq(:absolute)
        expect(profile[:scaling_style]).to eq(:early)
        expect(profile).to be_frozen
      end
    end

    context 'when symbol is SENSEX' do
      it 'returns the expected profile' do
        profile = described_class.for(:sensex)

        expect(profile[:allow_execution_only]).to eq(false)
        expect(profile[:max_lots_by_permission]).to eq(
          execution_only: 0,
          scale_ready: 1,
          full_deploy: 3
        )
        expect(profile[:target_model]).to eq(:convexity)
        expect(profile[:scaling_style]).to eq(:late)
        expect(profile).to be_frozen
      end
    end

    context 'when symbol is unsupported' do
      it 'raises' do
        expect { described_class.for('BANKNIFTY') }.to raise_error(
          Trading::InstrumentExecutionProfile::UnsupportedInstrumentError
        )
      end
    end
  end
end


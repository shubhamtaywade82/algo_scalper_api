# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomous::TaskRunner do
  describe '.apply_trailing_params' do
    let(:symbol) { 'NIFTY' }
    let(:params) do
      {
        early_trigger: 0.04,
        breakeven_trigger: 0.10,
        activation_trigger: 0.18,
        trailing_distance: 0.22
      }
    end

    before do
      allow(AlgoConfig::DocumentStore).to receive(:apply_deep_merge_patch!)
      allow(Rails.logger).to receive(:info)
    end

    context 'when dry_run is true' do
      it 'logs the parameters and does not write to DocumentStore' do
        described_class.send(:apply_trailing_params, symbol, params, dry_run: true)

        expect(Rails.logger).to have_received(:info).with(/Would apply trailing params to algo_config_document/)
        expect(AlgoConfig::DocumentStore).not_to have_received(:apply_deep_merge_patch!)
      end
    end

    context 'when dry_run is false' do
      it 'writes merged parameters via DocumentStore' do
        described_class.send(:apply_trailing_params, symbol, params, dry_run: false)

        expect(AlgoConfig::DocumentStore).to have_received(:apply_deep_merge_patch!).with(
          hash_including(
            risk: hash_including(
              institutional_trailing: hash_including(
                nifty: hash_including(early_trigger: 0.04, trailing_distance: 0.22)
              )
            )
          ),
          source: 'ai_autonomous_trailing',
          actor: 'TaskRunner',
          metadata: { index_key: 'nifty' }
        )
      end
    end
  end
end

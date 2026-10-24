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
    let(:config_hash) do
      {
        'risk' => {
          'institutional_trailing' => {
            'nifty' => { 'early_trigger' => 0.02 }
          }
        }
      }
    end

    before do
      # The runner edits config/algo.yml directly (TrailingOptimizer does not
      # self-persist), so intercept the file IO to keep the spec side-effect free.
      allow(YAML).to receive(:safe_load_file).and_return(config_hash)
      allow(File).to receive(:write)
      allow(Rails.logger).to receive(:info)
    end

    context 'when dry_run is true' do
      it 'logs the parameters and does not write to algo.yml' do
        described_class.send(:apply_trailing_params, symbol, params, dry_run: true)

        expect(Rails.logger).to have_received(:info)
          .with(/Would apply trailing params to algo\.yml for NIFTY/)
        expect(File).not_to have_received(:write)
      end
    end

    context 'when dry_run is false' do
      it 'writes merged parameters into config/algo.yml' do
        written_content = nil
        allow(File).to receive(:write) { |_path, content| written_content = content }

        described_class.send(:apply_trailing_params, symbol, params, dry_run: false)

        expect(File).to have_received(:write)
          .with(Rails.root.join('config/algo.yml'), kind_of(String))

        merged = YAML.safe_load(written_content)
        expect(merged.dig('risk', 'institutional_trailing', 'nifty')).to include(
          'early_trigger' => 0.04,
          'breakeven_trigger' => 0.10,
          'activation_trigger' => 0.18,
          'trailing_distance' => 0.22
        )
        expect(Rails.logger).to have_received(:info)
          .with('[TaskRunner] Applied trailing params to algo.yml for NIFTY')
      end
    end
  end
end

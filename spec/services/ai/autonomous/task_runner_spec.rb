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
      allow(Setting).to receive(:put)
      allow(AlgoConfig).to receive(:reset!)
    end

    context 'when dry_run is true' do
      it 'logs the parameters and does not write to the database or reset AlgoConfig' do
        allow(Rails.logger).to receive(:info)

        described_class.send(:apply_trailing_params, symbol, params, dry_run: true)

        expect(Rails.logger).to have_received(:info).with(/Would apply trailing params to database overrides/)
        expect(Setting).not_to have_received(:put)
        expect(AlgoConfig).not_to have_received(:reset!)
      end
    end

    context 'when dry_run is false' do
      # rubocop:disable RSpec/MultipleExpectations
      it 'writes merged parameters to database Settings and resets AlgoConfig' do
        existing_overrides = {
          'risk' => {
            'sl_pct' => 0.15,
            'institutional_trailing' => {
              'sensex' => { 'early_trigger' => 0.03 }
            }
          }
        }
        setting_stub = instance_double(Setting, value: existing_overrides.to_json)
        allow(Setting).to receive(:find_by).with(key: 'algo_config_overrides').and_return(setting_stub)

        described_class.send(:apply_trailing_params, symbol, params, dry_run: false)

        expect(Setting).to have_received(:put) do |key, value|
          expect(key).to eq('algo_config_overrides')
          parsed = JSON.parse(value)
          expect(parsed.dig('risk', 'sl_pct')).to eq(0.15)
          expect(parsed.dig('risk', 'institutional_trailing', 'sensex', 'early_trigger')).to eq(0.03)
          expect(parsed.dig('risk', 'institutional_trailing', 'nifty', 'early_trigger')).to eq(0.04)
          expect(parsed.dig('risk', 'institutional_trailing', 'nifty', 'trailing_distance')).to eq(0.22)
        end
        expect(AlgoConfig).to have_received(:reset!)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
  end
end

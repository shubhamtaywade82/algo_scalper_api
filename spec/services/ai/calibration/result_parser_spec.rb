# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Calibration::ResultParser do
  let(:raw_response) do
    {
      'system_diagnosis' => {
        'primary_failure' => 'SL too tight',
        'secondary_issues' => ['Late entries'],
        'most_lossy_regime' => 'volatile'
      },
      'parameter_changes' => [
        {
          'parameter' => 'sl_pct',
          'current' => 0.10,
          'suggested' => 0.15,
          'change' => 'increase',
          'reason' => 'High noise hits SL early',
          'confidence' => 0.85
        },
        {
          'parameter' => 'target_rr',
          'current' => 2.0,
          'suggested' => 3.0,
          'change' => 'increase',
          'reason' => 'Winners run further',
          'confidence' => 0.90
        }
      ],
      'regime_rules' => [
        { 'regime' => 'range', 'action' => 'disable_entries', 'reason' => 'Chop city' }
      ]
    }
  end

  describe '.call' do
    it 'parses and validates valid response' do
      result = described_class.call(raw_response)

      expect(result[:diagnosis]['primary_failure']).to eq('SL too tight')
      expect(result[:parameter_changes].size).to eq(2)
      expect(result[:proposed_patch]['risk']['sl_pct']).to eq(0.15)
      expect(result[:proposed_patch]['risk']['rr_profit_booking']['target_rr']).to eq(3.0)
    end

    it 'filters out low confidence suggestions' do
      raw_response['parameter_changes'] << {
        'parameter' => 'tp_pct',
        'current' => 0.25,
        'suggested' => 0.30,
        'change' => 'increase',
        'reason' => 'Weak evidence',
        'confidence' => 0.50
      }

      result = described_class.call(raw_response)
      expect(result[:parameter_changes].size).to eq(2)
      expect(result[:proposed_patch]['risk'].key?('tp_pct')).to be false
    end

    it 'filters out unknown parameters' do
      raw_response['parameter_changes'] << {
        'parameter' => 'hallucinated_param',
        'current' => 1,
        'suggested' => 2,
        'change' => 'increase',
        'reason' => 'AI hallucination',
        'confidence' => 0.99
      }

      result = described_class.call(raw_response)
      expect(result[:parameter_changes].size).to eq(2)
    end

    it 'enforces value bounds' do
      raw_response['parameter_changes'] << {
        'parameter' => 'sl_pct',
        'current' => 0.10,
        'suggested' => 0.99, # way too high
        'change' => 'increase',
        'reason' => 'Insane SL',
        'confidence' => 0.99
      }

      result = described_class.call(raw_response)
      expect(result[:parameter_changes].size).to eq(2)
    end

    it 'raises SchemaError if required keys missing' do
      expect { described_class.call({}) }.to raise_error(Ai::Calibration::ResultParser::SchemaError)
    end
  end
end

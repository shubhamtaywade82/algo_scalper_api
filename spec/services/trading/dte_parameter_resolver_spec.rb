# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DteParameterResolver do
  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        dte_parameters: {
          enabled: true,
          defaults: {
            sl_pct: 0.10,
            tp_pct: 0.45,
            trail_pct: 0.07,
            volume_velocity_multiplier: 2.0
          },
          by_dte: {
            '0' => {
              sl_pct: 0.08,
              tp_pct: 0.25,
              trail_pct: 0.05,
              volume_velocity_multiplier: 2.5,
              max_entry_time: '12:30'
            },
            '1' => {
              sl_pct: 0.10,
              tp_pct: 0.35,
              volume_velocity_multiplier: 2.5,
              max_entry_time: '14:00'
            }
          }
        }
      }
    )
  end

  describe '.resolve' do
    it 'returns 0-DTE tier parameters' do
      result = described_class.resolve(dte: 0)

      expect(result[:sl_pct]).to eq(0.08)
      expect(result[:max_entry_time]).to eq('12:30')
      expect(result[:volume_velocity_multiplier]).to eq(2.5)
    end

    it 'returns {} when the feature is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { dte_parameters: { enabled: false } })

      expect(described_class.resolve(dte: 0)).to eq({})
    end
  end

  describe '.risk_overrides_for' do
    it 'merges SL/TP into risk overrides for snapshot pinning' do
      overrides = described_class.risk_overrides_for(dte: 1)

      expect(overrides[:sl_pct]).to eq(0.10)
      expect(overrides[:tp_pct]).to eq(0.35)
    end
  end

  describe '.volume_velocity_multiplier' do
    it 'resolves the tier multiplier' do
      expect(described_class.volume_velocity_multiplier(dte: 0)).to eq(2.5)
    end

    it 'resolves the defaults multiplier when the tier omits it' do
      expect(described_class.volume_velocity_multiplier(dte: 7)).to eq(2.0)
    end

    it 'returns nil when the feature is disabled (documented outcome)' do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { dte_parameters: { enabled: false } })

      expect(described_class.volume_velocity_multiplier(dte: 0)).to be_nil
    end

    it 'raises when enabled but the multiplier is unconfigured — no assumed 2.0' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { dte_parameters: { enabled: true, defaults: {} } }
      )

      expect { described_class.volume_velocity_multiplier(dte: 0) }
        .to raise_error(Errors::ConfigurationError, /volume_velocity_multiplier/)
    end
  end
end

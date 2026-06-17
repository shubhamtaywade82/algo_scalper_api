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
  end

  describe '.risk_overrides_for' do
    it 'merges SL/TP into risk overrides for snapshot pinning' do
      overrides = described_class.risk_overrides_for(dte: 1)

      expect(overrides[:sl_pct]).to eq(0.10)
      expect(overrides[:tp_pct]).to eq(0.35)
    end
  end
end

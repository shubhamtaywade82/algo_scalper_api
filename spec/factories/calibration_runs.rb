# frozen_string_literal: true

FactoryBot.define do
  factory :calibration_run do
    symbol { 'NIFTY' }
    weeks_analyzed { 52 }
    strike_mode { 'atm_plus_minus' }
    raw_stats { {} }
    proposed_patch { {} }
    is_regime_shift { false }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :trade_telemetry do
    tracker { association :position_tracker }
    bos_age_at_entry { 5 }
    retrace_pct { 0.5 }
    pullback_candles { 3 }
    max_r_reached { 2.5 }
    exit_r { 2.0 }
    exit_path { 'target' }
    entry_tf { '5m' }
    htf_tf { '1h' }
    entry_time { Time.current }
    exit_time { Time.current + 10.minutes }
    index_key { 'NIFTY' }
  end
end

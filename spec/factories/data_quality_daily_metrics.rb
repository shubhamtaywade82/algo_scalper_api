FactoryBot.define do
  factory :data_quality_daily_metric do
    sequence(:trading_date) { |n| Date.current - n.days }
    missing_candle_count { 0 }
    candle_alignment_accuracy_pct { 100.0 }
    tick_staleness_rate_pct { 0.0 }
    instrument_mapping_accuracy_pct { 100.0 }
    expired_instrument_count { 0 }
    meta { {} }
  end
end

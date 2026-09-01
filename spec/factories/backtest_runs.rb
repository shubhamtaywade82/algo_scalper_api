# frozen_string_literal: true

FactoryBot.define do
  factory :backtest_run do
    symbol { 'NIFTY' }
    days_back { 30 }
    trading_type { 'options' }
    entry_interval { '5' }
    params { {} }
    status { 'pending' }
    results { {} }

    trait :completed do
      status { 'completed' }
      total_trades { 10 }
      win_rate { 55.0 }
      total_pnl { 12_500.5 }
      max_drawdown { 2_100.0 }
      started_at { 1.hour.ago }
      finished_at { 30.minutes.ago }
      results do
        {
          total_trades: 10, win_rate: 55.0, total_pnl: 12_500.5, max_drawdown: 2_100.0,
          trades: [{ entry_time: 1.hour.ago.iso8601, exit_time: 50.minutes.ago.iso8601, pnl: 1250.5, exit_reason: 'target' }]
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 1.hour.ago }
      finished_at { 55.minutes.ago }
      error_message { 'RuntimeError: Instrument NIFTY not found' }
    end
  end
end

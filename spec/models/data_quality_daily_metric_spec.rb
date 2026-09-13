# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataQualityDailyMetric do
  it 'requires a trading_date' do
    expect(build(:data_quality_daily_metric, trading_date: nil)).not_to be_valid
  end

  it 'enforces one row per trading_date' do
    create(:data_quality_daily_metric, trading_date: Date.current)

    expect(build(:data_quality_daily_metric, trading_date: Date.current)).not_to be_valid
  end

  it 'defaults counters to zero and meta to an empty hash' do
    metric = described_class.create!(trading_date: Date.current)

    expect(metric.missing_candle_count).to eq(0)
    expect(metric.expired_instrument_count).to eq(0)
    expect(metric.meta).to eq({})
  end

  describe '.recent_first' do
    it 'orders by trading_date descending' do
      older = create(:data_quality_daily_metric, trading_date: 2.days.ago.to_date)
      newer = create(:data_quality_daily_metric, trading_date: 1.day.ago.to_date)

      expect(described_class.recent_first.to_a).to eq([newer, older])
    end
  end
end

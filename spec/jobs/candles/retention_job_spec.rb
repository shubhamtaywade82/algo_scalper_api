# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::RetentionJob do
  def create_record(ts)
    Candles::Record.create!(
      instrument_key: 'NIFTY', exchange_segment: 'IDX_I', security_id: '13',
      timeframe: '1m', ts: ts, open: 100, high: 110, low: 90, close: 105, volume: 10
    )
  end

  it 'deletes 1m records older than 2 years' do
    old_record = create_record(2.years.ago - 1.day)
    recent_record = create_record(1.day.ago)

    described_class.perform_now

    expect(Candles::Record.exists?(old_record.id)).to be false
    expect(Candles::Record.exists?(recent_record.id)).to be true
  end

  it 'does not touch records exactly at the retention boundary or newer' do
    boundary_record = create_record(2.years.ago + 1.hour)

    described_class.perform_now

    expect(Candles::Record.exists?(boundary_record.id)).to be true
  end
end

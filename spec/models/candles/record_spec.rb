# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Record do
  let(:attrs) do
    {
      instrument_key: 'NIFTY',
      exchange_segment: 'IDX_I',
      security_id: '13',
      timeframe: '1m',
      ts: Time.zone.parse('2026-07-06 09:15:00'),
      open: 25_000.0,
      high: 25_050.0,
      low: 24_980.0,
      close: 25_020.0,
      volume: 0,
      source: 'live'
    }
  end

  it 'is valid with all required attributes' do
    expect(described_class.new(attrs)).to be_valid
  end

  it 'requires instrument_key, ts, and OHLC' do
    record = described_class.new
    record.valid?
    expect(record.errors.attribute_names).to include(:instrument_key, :ts, :open, :high, :low, :close)
  end

  it 'requires timeframe to be present even though the column defaults to "1m"' do
    # The migration's column default pre-fills `timeframe` on a bare `.new`, so the
    # presence validator never fires there. Force it blank to prove the validation
    # still catches an explicit nil/blank value.
    record = described_class.new(attrs.merge(timeframe: nil))
    record.valid?
    expect(record.errors.attribute_names).to include(:timeframe)
  end

  it 'enforces uniqueness on instrument_key + timeframe + ts' do
    described_class.create!(attrs)
    dup = described_class.new(attrs)
    expect(dup).not_to be_valid
    expect(dup.errors[:instrument_key]).to be_present
  end

  describe '.for_instrument' do
    it 'filters by instrument_key' do
      described_class.create!(attrs)
      described_class.create!(attrs.merge(instrument_key: 'BANKNIFTY', security_id: '25', ts: attrs[:ts] + 1.minute))

      expect(described_class.for_instrument('NIFTY').pluck(:instrument_key)).to eq(['NIFTY'])
    end
  end

  describe '.between' do
    it 'filters by ts range inclusively' do
      described_class.create!(attrs)
      from = attrs[:ts] - 1.minute
      to = attrs[:ts] + 1.minute

      expect(described_class.between(from, to).count).to eq(1)
      expect(described_class.between(attrs[:ts] + 1.second, to).count).to eq(0)
    end
  end
end

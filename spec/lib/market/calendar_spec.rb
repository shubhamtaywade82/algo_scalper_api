# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::Calendar do
  include ActiveSupport::Testing::TimeHelpers

  after { described_class.clear_holiday_cache! }

  describe '.trading_day?' do
    it 'returns false on Saturday' do
      expect(described_class.trading_day?(Date.new(2025, 1, 18))).to be false
    end

    it 'returns false on Sunday' do
      expect(described_class.trading_day?(Date.new(2025, 1, 19))).to be false
    end

    it 'returns true on a weekday without holiday override' do
      expect(described_class.trading_day?(Date.new(2025, 1, 15))).to be true
    end

    it 'returns false when date is listed under nse.holidays in config' do
      path = Rails.root.join('config', described_class::CONFIG_BASENAME)
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(path).and_return(true)
      allow(YAML).to receive(:safe_load_file).with(
        path,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: true
      ).and_return({ 'nse' => { 'holidays' => ['2030-01-02'] } })

      described_class.clear_holiday_cache!
      expect(described_class.trading_day?(Date.new(2030, 1, 2))).to be false
      expect(described_class.trading_day?(Date.new(2030, 1, 3))).to be true
    end

    it 'returns false when date exists in market_holidays' do
      create(:market_holiday, exchange: :nse, observed_on: Date.new(2033, 8, 16), name: 'DB-only holiday')
      described_class.clear_holiday_cache!
      expect(described_class.trading_day?(Date.new(2033, 8, 16))).to be false
    end
  end

  describe '.next_trading_day' do
    it 'skips weekend' do
      travel_to Time.zone.parse('2025-01-17 12:00:00 +05:30') do # Friday
        n = described_class.next_trading_day
        expect(n).to eq(Date.new(2025, 1, 20))
      end
    end
  end

  describe '.on_or_before_trading_day' do
    it 'returns the same date on a weekday' do
      expect(described_class.on_or_before_trading_day(Date.new(2026, 6, 18))).to eq(Date.new(2026, 6, 18))
    end

    it 'returns the previous Friday for a Saturday' do
      expect(described_class.on_or_before_trading_day(Date.new(2026, 5, 9))).to eq(Date.new(2026, 5, 8))
    end
  end
end

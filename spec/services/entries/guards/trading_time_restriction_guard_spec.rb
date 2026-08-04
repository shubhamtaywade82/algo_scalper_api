# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::TradingTimeRestrictionGuard do
  include ActiveSupport::Testing::TimeHelpers

  describe '.call' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        trading_time_restrictions: {
          enabled: true,
          avoid_periods: ['11:00-13:45'],
          block_exits: false
        }
      )
      AlgoConfig.reset!
    end

    it 'blocks during configured avoid period' do
      travel_to Time.zone.parse('2025-01-15 12:00:00 +05:30') do
        result = described_class.call({})
        expect(result).to eq(blocked: 'session blackout 11:00-13:45 (trading_time_restrictions)')
      end
    end

    it 'passes outside avoid period' do
      travel_to Time.zone.parse('2025-01-15 10:30:00 +05:30') do
        expect(described_class.call({})).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    it 'passes when restrictions disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        trading_time_restrictions: { enabled: false, avoid_periods: ['11:00-13:45'] }
      )
      AlgoConfig.reset!

      travel_to Time.zone.parse('2025-01-15 12:00:00 +05:30') do
        expect(described_class.call({})).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end

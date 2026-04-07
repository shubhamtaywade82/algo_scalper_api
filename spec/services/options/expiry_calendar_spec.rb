# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ExpiryCalendar do
  describe '.windows' do
    context 'with Thursday expiry dates (NIFTY-like)' do
      # Real dates — no weekday assumptions, just actual data from DhanHQ
      let(:expiry_dates) { ['2026-03-26', '2026-03-19', '2026-03-12'] } # Thursdays

      it 'returns one window per expiry date, oldest first' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        expect(windows.size).to eq(3)
        expect(windows.map { |w| w[:expiry] }).to eq(expiry_dates.map { |d| Date.parse(d) }.sort)
      end

      it 'sets to: equal to the expiry date' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        windows.each { |w| expect(w[:to]).to eq(w[:expiry]) }
      end

      it 'sets from: to Monday of the expiry week' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        windows.each do |w|
          expect(w[:from].wday).to eq(1), "expected Monday, got #{w[:from].strftime('%A')}"
          expect(w[:from]).to eq(w[:expiry] - (w[:expiry].wday - 1).days)
        end
      end
    end

    context 'with Wednesday expiry dates (SENSEX-like)' do
      let(:expiry_dates) { ['2026-03-25', '2026-03-18', '2026-03-11'] } # Wednesdays

      it 'derives correct Monday-to-Wednesday windows without any weekday hardcoding' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        windows.each do |w|
          expect(w[:expiry].wday).to eq(3), "expected Wednesday"
          expect(w[:from].wday).to eq(1), "expected Monday start"
        end
      end
    end

    context 'when a holiday shifts expiry (e.g. Wednesday instead of Thursday)' do
      let(:expiry_dates) { ['2026-03-25'] } # Wednesday — holiday-shifted from Thursday

      it 'uses the actual shifted date without assuming the usual weekday' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        expect(windows.first[:expiry].wday).to eq(3) # Wednesday
        expect(windows.first[:from].wday).to eq(1)   # still starts Monday
      end
    end

    context 'with mixed Date, String, and Time inputs' do
      let(:expiry_dates) do
        [Date.new(2026, 3, 26), '2026-03-19', Time.zone.parse('2026-03-12 15:30')]
      end

      it 'coerces all types to Date' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        expect(windows.size).to eq(3)
        windows.each { |w| expect(w[:expiry]).to be_a(Date) }
      end
    end

    context 'with duplicate or nil entries' do
      let(:expiry_dates) { ['2026-03-26', '2026-03-26', nil, '2026-03-19'] }

      it 'deduplicates and ignores nils' do
        windows = described_class.windows(expiry_dates: expiry_dates)
        expect(windows.size).to eq(2)
      end
    end

    context 'with an empty array' do
      it 'returns an empty array' do
        expect(described_class.windows(expiry_dates: [])).to eq([])
      end
    end

    context 'when called without expiry_dates keyword' do
      it 'raises ArgumentError' do
        expect { described_class.windows(expiry_dates: nil) }.to raise_error(ArgumentError)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ExpiryCalendar do
  describe '.windows' do
    context 'for NIFTY (Thursday expiry)' do
      it 'returns windows with Thursday expiry dates' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 4)
        expect(windows.size).to eq(4)
        windows.each do |w|
          expect(w[:expiry].wday).to eq(4), "expected Thursday, got #{w[:expiry].strftime('%A')}"
        end
      end

      it 'each window spans 6 days ending on expiry (from = expiry - 6.days)' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 2)
        windows.each do |w|
          expect(w[:to]).to eq(w[:expiry])
          expect(w[:from]).to eq(w[:expiry] - 6.days)
        end
      end

      it 'returns windows in ascending order (oldest first)' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 4)
        dates = windows.pluck(:expiry)
        expect(dates).to eq(dates.sort)
      end
    end

    context 'for SENSEX (Friday expiry)' do
      it 'returns windows with Friday expiry dates' do
        windows = described_class.windows(symbol: 'SENSEX', weeks: 4)
        windows.each do |w|
          expect(w[:expiry].wday).to eq(5), "expected Friday, got #{w[:expiry].strftime('%A')}"
        end
      end
    end

    context 'when run on the expiry day itself' do
      it 'includes the current week as the most recent window' do
        thursday = Date.new(2026, 3, 12) # A Thursday
        allow(Time.zone).to receive(:today).and_return(thursday)
        windows = described_class.windows(symbol: 'NIFTY', weeks: 1)
        expect(windows.last[:expiry]).to eq(thursday)
      end
    end

    context 'with an unknown symbol' do
      it 'raises ArgumentError' do
        expect do
          described_class.windows(symbol: 'UNKNOWN', weeks: 4)
        end.to raise_error(ArgumentError, /unknown symbol/)
      end
    end
  end
end

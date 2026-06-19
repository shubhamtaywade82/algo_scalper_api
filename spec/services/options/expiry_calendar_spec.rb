# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ExpiryCalendar do
  describe '.windows' do
    context 'for NIFTY (Thursday expiry)' do
      it 'returns windows with Thursday expiry dates' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 4)
        expect(windows.size).to eq(4)
        windows.each do |window|
          expect(window[:expiry].wday).to eq(4)
        end
      end

      it 'each window spans 6 days ending on expiry' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 2)
        windows.each do |window|
          expect(window[:to]).to eq(window[:expiry])
          expect(window[:from]).to eq(window[:expiry] - 6.days)
        end
      end
    end

    context 'for SENSEX (Friday expiry)' do
      it 'returns windows with Friday expiry dates' do
        windows = described_class.windows(symbol: 'SENSEX', weeks: 4)
        windows.each do |window|
          expect(window[:expiry].wday).to eq(5)
        end
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

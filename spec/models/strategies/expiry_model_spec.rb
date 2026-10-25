# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::ExpiryModel do
  describe '.session' do
    def session_at(hour, minute)
      travel_to(Time.zone.parse("2026-10-26 #{format('%02d', hour)}:#{format('%02d', minute)} +05:30")) do
        described_class.session
      end
    end

    it 'maps market hours to the expected sessions' do
      expect(session_at(9, 15)).to eq(:morning)
      expect(session_at(10, 29)).to eq(:morning)
      expect(session_at(10, 30)).to eq(:midday)
      expect(session_at(12, 59)).to eq(:midday)
      expect(session_at(13, 0)).to eq(:afternoon)
      expect(session_at(14, 29)).to eq(:afternoon)
      expect(session_at(14, 30)).to eq(:gamma_session)
      expect(session_at(15, 30)).to eq(:gamma_session)
    end

    it 'reports :closed outside market hours' do
      expect(session_at(8, 0)).to eq(:closed)
      expect(session_at(15, 31)).to eq(:closed)
      expect(session_at(22, 0)).to eq(:closed)
    end
  end

  describe '.trade_allowed?' do
    it 'allows trading during morning sessions on non-expiry days' do
      allow(described_class).to receive(:expiry_day?).and_return(false)
      travel_to(Time.zone.parse('2026-10-26 10:00:00 +05:30')) do
        expect(described_class.trade_allowed?(symbol: 'NIFTY')).to be(true)
      end
    end

    it 'blocks trading when the market is closed' do
      allow(described_class).to receive(:expiry_day?).and_return(false)
      travel_to(Time.zone.parse('2026-10-26 16:00:00 +05:30')) do
        expect(described_class.trade_allowed?(symbol: 'NIFTY')).to be(false)
      end
    end

    it 'blocks the midday decay window on expiry days' do
      allow(described_class).to receive(:expiry_day?).and_return(true)
      travel_to(Time.zone.parse('2026-10-26 12:00:00 +05:30')) do
        expect(described_class.trade_allowed?(symbol: 'NIFTY')).to be(false)
      end
    end

    it 'allows morning entries on expiry days' do
      allow(described_class).to receive(:expiry_day?).and_return(true)
      travel_to(Time.zone.parse('2026-10-26 10:00:00 +05:30')) do
        expect(described_class.trade_allowed?(symbol: 'NIFTY')).to be(true)
      end
    end
  end

  describe '.expiry_day?' do
    it 'returns false for a blank symbol' do
      expect(described_class.expiry_day?(nil)).to be(false)
      expect(described_class.expiry_day?('')).to be(false)
    end

    it 'delegates to Market::ExpiryChecker' do
      allow(Market::ExpiryChecker).to receive(:expiry_today?).with('NIFTY').and_return(true)
      expect(described_class.expiry_day?('NIFTY')).to be(true)
      expect(Market::ExpiryChecker).to have_received(:expiry_today?).with('NIFTY')
    end
  end
end

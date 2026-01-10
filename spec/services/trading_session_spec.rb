# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSession::Service do
  include ActiveSupport::Testing::TimeHelpers

  describe '.market_closed?' do
    context 'when market is closed (after 3:30 PM IST)' do
      it 'returns true at exactly 3:30 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:30:00 +05:30') do
          expect(described_class.market_closed?).to be true
        end
      end

      it 'returns true at 3:30:01 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:30:01 +05:30') do
          expect(described_class.market_closed?).to be true
        end
      end

      it 'returns true at 4:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 16:00:00 +05:30') do
          expect(described_class.market_closed?).to be true
        end
      end

      it 'returns true at 11:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 23:00:00 +05:30') do
          expect(described_class.market_closed?).to be true
        end
      end

      it 'returns false at midnight (before 3:30 PM, so not closed)' do
        travel_to Time.zone.parse('2025-01-16 00:00:00 +05:30') do
          # Midnight (hour 0) is before 3:30 PM (hour 15), so market_closed? returns false
          # market_closed? checks if time is AFTER 3:30 PM, not if market is open
          expect(described_class.market_closed?).to be false
        end
      end
    end

    context 'when market is open (before 3:30 PM IST)' do
      it 'returns false at 9:20 AM IST' do
        travel_to Time.zone.parse('2025-01-15 09:20:00 +05:30') do
          expect(described_class.market_closed?).to be false
        end
      end

      it 'returns false at 12:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 12:00:00 +05:30') do
          expect(described_class.market_closed?).to be false
        end
      end

      it 'returns false at 3:29:59 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:29:59 +05:30') do
          expect(described_class.market_closed?).to be false
        end
      end

      it 'returns false at 3:29 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:29:00 +05:30') do
          expect(described_class.market_closed?).to be false
        end
      end
    end
  end

  describe '.market_open?' do
    it 'returns opposite of market_closed?' do
      travel_to Time.zone.parse('2025-01-15 15:30:00 +05:30') do
        expect(described_class.market_open?).to eq(!described_class.market_closed?)
      end
    end
  end

  describe '.entry_allowed?' do
    context 'when before entry start time (9:20 AM)' do
      it 'returns false with appropriate reason' do
        travel_to Time.zone.parse('2025-01-15 09:19:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be false
          expect(result[:reason]).to include('Entry not allowed before')
        end
      end
    end

    context 'when during entry window (9:20 AM to 3:15 PM)' do
      it 'returns true at 9:20 AM IST' do
        travel_to Time.zone.parse('2025-01-15 09:20:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be true
          expect(result[:reason]).to include('Entry allowed')
        end
      end

      it 'returns true at 12:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 12:00:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be true
        end
      end

      it 'returns true at 3:14 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:14:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be true
        end
      end
    end

    context 'when after entry end time (3:15 PM)' do
      it 'returns false at 3:15 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:15:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be false
          expect(result[:reason]).to include('Entry not allowed after')
        end
      end

      it 'returns false at 4:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 16:00:00 +05:30') do
          result = described_class.entry_allowed?
          expect(result[:allowed]).to be false
        end
      end
    end
  end

  describe '.should_force_exit?' do
    context 'when before exit deadline (3:15 PM)' do
      it 'returns false with time remaining' do
        travel_to Time.zone.parse('2025-01-15 15:00:00 +05:30') do
          result = described_class.should_force_exit?
          expect(result[:should_exit]).to be false
          expect(result[:time_remaining]).to be > 0
        end
      end
    end

    context 'when at or after exit deadline (3:15 PM)' do
      it 'returns true at 3:15 PM IST' do
        travel_to Time.zone.parse('2025-01-15 15:15:00 +05:30') do
          result = described_class.should_force_exit?
          expect(result[:should_exit]).to be true
          expect(result[:time_remaining]).to eq(0)
          expect(result[:reason]).to include('Session end deadline reached')
        end
      end

      it 'returns true at 4:00 PM IST' do
        travel_to Time.zone.parse('2025-01-15 16:00:00 +05:30') do
          result = described_class.should_force_exit?
          expect(result[:should_exit]).to be true
        end
      end
    end
  end

  describe '.in_session?' do
    it 'returns true when entry is allowed' do
      travel_to Time.zone.parse('2025-01-15 12:00:00 +05:30') do
        expect(described_class.in_session?).to be true
      end
    end

    it 'returns false when entry is not allowed' do
      travel_to Time.zone.parse('2025-01-15 16:00:00 +05:30') do
        expect(described_class.in_session?).to be false
      end
    end
  end

  describe '.seconds_until_session_end' do
    it 'returns positive seconds before 3:15 PM' do
      travel_to Time.zone.parse('2025-01-15 15:00:00 +05:30') do
        seconds = described_class.seconds_until_session_end
        expect(seconds).to be > 0
        expect(seconds).to be <= 900 # 15 minutes = 900 seconds
      end
    end

    it 'returns 0 at or after 3:15 PM' do
      travel_to Time.zone.parse('2025-01-15 15:15:00 +05:30') do
        expect(described_class.seconds_until_session_end).to eq(0)
      end
    end
  end

  describe '.current_ist_time' do
    it 'returns time in IST timezone' do
      time = described_class.current_ist_time
      expect(time.time_zone.name).to eq('Asia/Kolkata')
    end
  end
end

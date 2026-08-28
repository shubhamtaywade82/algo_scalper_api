# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TimeRegimeService do
  subject(:service) { described_class.instance }

  describe '#allow_new_trades?' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: {
          time_overrides: {
            earliest_entry_time: '09:30',
            no_new_trades_after: '15:05'
          },
          time_regimes: { enabled: true, trend_continuation: { allow_entries: true } }
        }
      )
      allow(service).to receive(:allow_new_trades?).and_call_original
      allow(service).to receive(:allow_entries?).and_return(true)
    end

    context 'when before earliest entry time' do
      it 'returns false at 09:20 IST' do
        time = Time.zone.parse('2026-03-17 09:20:00 +05:30')

        expect(service.allow_new_trades?(time: time)).to be(false)
      end
    end

    context 'when at or after earliest entry time' do
      it 'returns true at 09:30 IST' do
        time = Time.zone.parse('2026-03-17 09:30:00 +05:30')

        expect(service.allow_new_trades?(time: time)).to be(true)
      end
    end
  end
end

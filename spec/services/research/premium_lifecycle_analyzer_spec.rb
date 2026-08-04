# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::PremiumLifecycleAnalyzer do
  def bar(minute, open:, high:, low:, close:)
    { ts: Time.zone.parse('2026-07-10 09:15:00') + minute.minutes, open: open, high: high, low: low, close: close }
  end

  describe '.analyze' do
    it 'returns no_data when nothing exists at/after the entry timestamp' do
      bars = [bar(0, open: 100, high: 105, low: 98, close: 101)]
      result = described_class.analyze(bars, entry_ts: Time.zone.parse('2026-07-10 10:00:00'))

      expect(result).to eq(status: 'no_data')
    end

    it 'traces entry -> peak -> decay -> end and computes return/drawdown/threshold metrics' do
      bars = [
        bar(0,  open: 180, high: 182, low: 178, close: 180), # entry
        bar(30, open: 250, high: 270, low: 245, close: 260), # +100% threshold crossed here
        bar(77, open: 400, high: 418, low: 395, close: 410), # peak (418)
        bar(80, open: 405, high: 408, low: 398, close: 401),
        bar(85, open: 398, high: 399, low: 340, close: 350), # below 90% of peak (376.2) and stays below
        bar(95, open: 300, high: 305, low: 275, close: 280),
        bar(105, open: 250, high: 255, low: 185, close: 190) # end
      ]

      result = described_class.analyze(bars, entry_ts: bars.first[:ts])

      expect(result[:status]).to eq('computed')
      expect(result[:entry_premium]).to eq(180.0)
      expect(result[:peak_premium]).to eq(418.0)
      expect(result[:minutes_to_peak]).to eq(77)
      expect(result[:peak_return_pct]).to be_within(0.01).of(((418.0 - 180.0) / 180.0) * 100)
      expect(result[:decay_start_ts]).to eq(bars[4][:ts]) # first bar whose close (350) never recovers above 376.2
      expect(result[:end_premium]).to eq(190.0)
      expect(result[:end_return_pct]).to be_within(0.01).of(((190.0 - 180.0) / 180.0) * 100)
      expect(result[:max_drawdown_after_peak_pct]).to be_within(0.01).of(((418.0 - 185.0) / 418.0) * 100)

      thresholds = result[:threshold_minutes]
      expect(thresholds['25']).to eq(30)  # target 225, first reached by the 30-min bar (high 270)
      expect(thresholds['50']).to eq(30)  # target 270, met exactly by the 30-min bar
      expect(thresholds['100']).to eq(77) # target 360, only the 77-min peak bar (high 418) reaches it
      expect(thresholds['150']).to be_nil # target 450, never reached (peak high is 418)
      expect(thresholds['300']).to be_nil # target 720, never reached
    end

    it 'ignores bars whose actual_strike differs from the entry bar' do
      # DhanHQ's rolling "ATM" series can splice in a different strike's bar mid-window (spot
      # wiggled across a boundary). Without filtering, that bar's price would corrupt peak/decay
      # as if it were the same held contract.
      bars = [
        { ts: Time.zone.parse('2026-07-10 09:15:00'), open: 180, high: 182, low: 178, close: 180, actual_strike: 25_000 },
        { ts: Time.zone.parse('2026-07-10 09:20:00'), open: 999, high: 999, low: 999, close: 999, actual_strike: 25_050 },
        { ts: Time.zone.parse('2026-07-10 09:25:00'), open: 250, high: 260, low: 245, close: 255, actual_strike: 25_000 }
      ]

      result = described_class.analyze(bars, entry_ts: bars.first[:ts])

      expect(result[:peak_premium]).to eq(260.0)
      expect(result[:end_premium]).to eq(255.0)
    end
  end
end

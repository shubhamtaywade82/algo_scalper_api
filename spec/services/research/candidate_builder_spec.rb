# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::CandidateBuilder do
  let(:signal) do
    Research::Signal.create!(
      underlying_symbol: 'NIFTY',
      signal_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
      direction: 'bullish',
      spot_price: 24_982
    )
  end

  describe '.build' do
    it 'creates CE candidates for a bullish signal across ATM+/-max_distance' do
      candidates = described_class.build(signal: signal, expiry_flags: ['WEEK'], max_distance: 1)

      expect(candidates.size).to eq(3)
      expect(candidates.map(&:option_type)).to all(eq('CE'))
      expect(candidates.map(&:strike_label)).to contain_exactly('ATM-1', 'ATM', 'ATM+1')
      expect(candidates.map(&:status)).to all(eq('pending'))
    end

    it 'creates PE candidates for a bearish signal' do
      signal.update!(direction: 'bearish')
      candidates = described_class.build(signal: signal, expiry_flags: ['WEEK'], max_distance: 0)

      expect(candidates.size).to eq(1)
      expect(candidates.first.option_type).to eq('PE')
      expect(candidates.first.actual_strike.to_f).to eq(25_000.0)
    end

    it 'returns no candidates for a no_trade signal' do
      signal.update!(direction: 'no_trade')
      expect(described_class.build(signal: signal)).to eq([])
    end

    it 'is idempotent for the same signal/expiry/entry_model' do
      described_class.build(signal: signal, expiry_flags: ['WEEK'], max_distance: 1)
      expect do
        described_class.build(signal: signal, expiry_flags: ['WEEK'], max_distance: 1)
      end.not_to change(Research::OptionCandidate, :count)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

class SessionDetectorTestHarness
  include SessionDetector
end

RSpec.describe SessionDetector do
  subject(:detector) { SessionDetectorTestHarness.new }

  let(:time_regimes) do
    {
      open_expansion: { start: '09:15', end: '09:45' },
      trend_continuation: { start: '09:45', end: '11:30' },
      chop_decay: { start: '11:30', end: '13:45' },
      close_gamma: { start: '13:45', end: '15:15' }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { time_regimes: time_regimes }
    })
  end

  context 'when in open_expansion (09:30 IST)' do
    before { allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 09:30:00 +05:30')) }

    it('returns :open_expansion') { expect(detector.detect_current_session).to eq(:open_expansion) }
  end

  context 'when in chop_decay (12:00 IST)' do
    before { allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30')) }

    it('returns :chop_decay') { expect(detector.detect_current_session).to eq(:chop_decay) }
  end

  context 'when in close_gamma (14:00 IST)' do
    before { allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 14:00:00 +05:30')) }

    it('returns :close_gamma') { expect(detector.detect_current_session).to eq(:close_gamma) }
  end

  context 'when outside all sessions (08:00 IST)' do
    before { allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 08:00:00 +05:30')) }

    it('returns nil') { expect(detector.detect_current_session).to be_nil }
  end

  context 'when time_regimes config is missing' do
    before { allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} }) }

    it('returns nil') { expect(detector.detect_current_session).to be_nil }
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TimeRegimeService do
  subject(:service) { described_class.instance }

  # Mirrors the shipped config/algo.yml shape: the section lives under risk:
  # (NOT the top-level :time_regimes key the service used to read — the
  # mismatch silently killed every regime lookup; see error-handling wave 4).
  let(:regimes_config) do
    {
      enabled: true,
      open_expansion: { start: '09:15', end: '09:45', allow_entries: true },
      trend_continuation: { start: '09:45', end: '11:30', allow_entries: true },
      chop_decay: { start: '11:30', end: '13:45', allow_entries: false },
      close_gamma: { start: '13:45', end: '15:15', allow_entries: true }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        time_overrides: {
          earliest_entry_time: '09:30',
          no_new_trades_after: '15:05'
        },
        time_regimes: regimes_config
      }
    )
  end

  describe '#current_regime' do
    it 'classifies from risk.time_regimes (the path the config actually ships)' do
      time = Time.zone.parse('2026-03-17 12:00:00 +05:30')

      expect(service.current_regime(time: time)).to eq(:chop_decay)
    end

    it 'returns pre/post market symbols outside the session' do
      expect(service.current_regime(time: Time.zone.parse('2026-03-17 08:00:00 +05:30'))).to eq(:pre_market)
      expect(service.current_regime(time: Time.zone.parse('2026-03-17 16:00:00 +05:30'))).to eq(:post_market)
    end

    context 'when rules are disabled' do
      let(:regimes_config) { { enabled: false, chop_decay: { start: '11:30', end: '13:45', allow_entries: false } } }

      it 'falls back to the documented no-rules profile' do
        time = Time.zone.parse('2026-03-17 12:00:00 +05:30')

        expect(service.current_regime(time: time)).to eq(:trend_continuation)
      end
    end

    context 'when enabled but the section is absent' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: {})
      end

      it 'falls back to the documented no-rules profile' do
        time = Time.zone.parse('2026-03-17 12:00:00 +05:30')

        expect(service.current_regime(time: time)).to eq(:trend_continuation)
      end
    end

    context 'when enabled with a coverage gap' do
      let(:regimes_config) { { enabled: true, open_expansion: { start: '09:15', end: '09:45', allow_entries: true } } }

      it 'raises instead of guessing trend continuation' do
        time = Time.zone.parse('2026-03-17 12:00:00 +05:30')

        expect { service.current_regime(time: time) }
          .to raise_error(Errors::ConfigurationError, /no regime window covers 12:00/)
      end
    end

    context 'when a window is malformed' do
      let(:regimes_config) { { enabled: true, open_expansion: { start: '9:15', end: '09:45', allow_entries: true } } }

      it 'raises ConfigurationError on non-zero-padded times' do
        time = Time.zone.parse('2026-03-17 09:20:00 +05:30')

        expect { service.current_regime(time: time) }
          .to raise_error(Errors::ConfigurationError, /zero-padded/)
      end
    end

    context 'when a window is missing its end time' do
      let(:regimes_config) { { enabled: true, open_expansion: { start: '09:15', allow_entries: true } } }

      it 'raises ConfigurationError instead of skipping the window' do
        time = Time.zone.parse('2026-03-17 09:20:00 +05:30')

        expect { service.current_regime(time: time) }
          .to raise_error(Errors::ConfigurationError, /open_expansion\.end/)
      end
    end
  end

  describe '#allow_new_trades?' do
    it 'returns false before the earliest entry time' do
      time = Time.zone.parse('2026-03-17 09:20:00 +05:30')

      expect(service.allow_new_trades?(time: time)).to be(false)
    end

    it 'returns true inside the window when the regime allows entries' do
      time = Time.zone.parse('2026-03-17 09:30:00 +05:30')

      expect(service.allow_new_trades?(time: time)).to be(true)
    end

    it 'returns false when the current regime bans entries (chop_decay)' do
      time = Time.zone.parse('2026-03-17 12:00:00 +05:30')

      expect(service.allow_new_trades?(time: time)).to be(false)
    end

    it 'returns false after the no-new-trades cutoff' do
      time = Time.zone.parse('2026-03-17 15:05:00 +05:30')

      expect(service.allow_new_trades?(time: time)).to be(false)
    end
  end

  describe 'malformed time overrides' do
    it 'raises instead of silently mis-ordering the string comparison' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { time_overrides: { no_new_trades_after: '2:50' }, time_regimes: regimes_config }
      )
      time = Time.zone.parse('2026-03-17 10:00:00 +05:30')

      expect { service.allow_new_trades?(time: time) }
        .to raise_error(Errors::ConfigurationError, /no_new_trades_after/)
    end
  end

  describe '#rules_enabled?' do
    it 'reflects the enabled flag' do
      expect(service.rules_enabled?).to be(true)
    end

    it 'is false when the section is absent' do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: {})

      expect(service.rules_enabled?).to be(false)
    end
  end

  describe '#allow_entries? / #allow_trailing?' do
    it 'honours the per-regime flags from config' do
      expect(service.allow_entries?(:chop_decay)).to be(false)
      expect(service.allow_entries?(:open_expansion)).to be(true)
    end

    it 'treats an absent flag as allowed (documented per-regime default)' do
      expect(service.allow_trailing?(:chop_decay)).to be(true)
    end
  end
end

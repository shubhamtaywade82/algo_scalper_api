# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Policies::EntryPolicy do
  let(:index_cfg) { { key: 'NIFTY' } }

  subject(:policy) { described_class.new(index_cfg: index_cfg, direction: :long) }

  # ── Helpers: stub all checks to pass by default ─────────────────────────────

  before do
    allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    allow_any_instance_of(Live::DailyLimits).to receive(:can_trade?)
      .and_return({ allowed: true })
    # Freeze time inside market hours (10:00 IST)
    travel_to(Time.zone.parse('2026-01-13 10:00:00 +0530'))
  end

  after { travel_back }

  # ── Permitted: all checks pass ──────────────────────────────────────────────

  describe '#permitted? — all clear' do
    it { is_expected.to be_permitted }
    it { expect(policy.reasons).to be_empty }
    it { expect { policy.authorize! }.not_to raise_error }
  end

  # ── Circuit breaker tripped ─────────────────────────────────────────────────

  context 'when circuit breaker is tripped' do
    before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('circuit_breaker_tripped') }
  end

  # ── Outside trading hours ───────────────────────────────────────────────────

  context 'when outside market hours' do
    before { travel_to(Time.zone.parse('2026-01-13 08:00:00 +0530')) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('outside_trading_hours') }
  end

  # ── Daily loss limit reached ────────────────────────────────────────────────

  context 'when daily loss limit is reached' do
    before do
      allow_any_instance_of(Live::DailyLimits).to receive(:can_trade?)
        .and_return({ allowed: false, reason: 'daily_loss_limit_reached' })
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('daily_loss_limit_reached') }
  end

  # ── Multiple violations ─────────────────────────────────────────────────────

  context 'with multiple violations' do
    before do
      allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true)
      travel_to(Time.zone.parse('2026-01-13 08:00:00 +0530'))
    end

    it 'reports all violations' do
      expect(policy.reasons).to include('circuit_breaker_tripped', 'outside_trading_hours')
    end
  end

  # ── authorize! ──────────────────────────────────────────────────────────────

  describe '#authorize!' do
    context 'when forbidden' do
      before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

      it 'raises PolicyViolationError' do
        expect { policy.authorize! }.to raise_error(Policies::BasePolicy::PolicyViolationError)
      end
    end
  end
end

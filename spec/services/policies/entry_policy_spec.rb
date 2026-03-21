# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Policies::EntryPolicy do
  subject(:policy) { described_class.new(index_cfg: index_cfg, direction: :long) }

  let(:index_cfg) { { key: 'NIFTY' } }
  let(:current_time) { Time.zone.now.change(hour: 10, min: 0, sec: 0) }
  let(:daily_limits) { instance_double(Live::DailyLimits) }

  before do
    allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(daily_limits).to receive(:can_trade?)
      .and_return({ allowed: true, reason: nil })
    allow(Time).to receive(:current).and_return(current_time)
  end

  describe '#permitted? — all clear' do
    it { is_expected.to be_permitted }
    it { expect(policy.reasons).to be_empty }
    it { expect { policy.authorize! }.not_to raise_error }
  end

  context 'when circuit breaker is tripped' do
    before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('circuit_breaker_tripped') }
  end

  context 'when outside market hours' do
    let(:current_time) { Time.zone.now.change(hour: 8, min: 0, sec: 0) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('outside_trading_hours') }
  end

  context 'when daily loss limit is reached' do
    before do
      allow(daily_limits).to receive(:can_trade?)
        .and_return({ allowed: false, reason: 'daily_loss_limit_reached' })
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('daily_loss_limit_reached') }
  end

  context 'when only trade frequency limit is exceeded' do
    before do
      allow(daily_limits).to receive(:can_trade?)
        .and_return({ allowed: false, reason: 'trade_frequency_limit_exceeded' })
    end

    it { is_expected.to be_permitted }
    it { expect(policy.reasons).not_to include('daily_loss_limit_reached') }
  end

  context 'with multiple violations' do
    before do
      allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true)
    end

    let(:current_time) { Time.zone.now.change(hour: 8, min: 0, sec: 0) }

    it 'reports all violations' do
      expect(policy.reasons).to include('circuit_breaker_tripped', 'outside_trading_hours')
    end
  end

  describe '#authorize!' do
    context 'when forbidden' do
      before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

      it 'raises PolicyViolationError' do
        expect { policy.authorize! }.to raise_error(Policies::BasePolicy::PolicyViolationError)
      end
    end
  end
end

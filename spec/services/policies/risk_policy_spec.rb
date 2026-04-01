# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe Policies::RiskPolicy do
  subject(:policy) do
    described_class.new(
      index_key: 'NIFTY',
      proposed_qty: 50,
      entry_price: 250.0
    )
  end

  let(:active_count) { 0 }
  let(:active_scope) { instance_double(ActiveRecord::Relation, count: active_count) }
  let(:daily_limit_result) { { allowed: true } }
  let(:daily_limits) { instance_double(Live::DailyLimits, can_trade?: daily_limit_result) }
  let(:wallet_snapshot) { { equity: 500_000.0, exposure: 50_000.0 } }
  let(:gateway) { instance_double(Orders::GatewayPaper, wallet_snapshot: wallet_snapshot) }

  before do
    allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    allow(Positions::ActiveForExit).to receive(:call).and_return(active_scope)
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(AlgoConfig).to receive(:fetch).and_return(
      { risk: { max_active_positions: 3, max_exposure_pct: 0.30 } }
    )
    allow(Orders).to receive(:config).and_return(OpenStruct.new(gateway: gateway))
  end

  describe '#permitted? — all checks pass' do
    it { is_expected.to be_permitted }
    it { expect(policy.reasons).to be_empty }
  end

  context 'when proposed_qty is NaN' do
    subject(:policy) do
      described_class.new(
        index_key: 'NIFTY',
        proposed_qty: Float::NAN,
        entry_price: 250.0
      )
    end

    it 'coerces to zero without raising' do
      expect { policy.permitted? }.not_to raise_error
      expect(policy).to be_permitted
    end
  end

  context 'when circuit breaker is tripped' do
    before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('circuit_breaker_tripped') }
  end

  context 'when max active positions are open' do
    let(:active_count) { 3 }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('max_active_positions_exceeded') }
  end

  context 'when per-trade risk would exceed configured limit' do
    let(:wallet_snapshot) { { equity: 100_000.0, exposure: 10_000.0 } }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        { risk: { max_active_positions: 3, max_exposure_pct: 1.0, per_trade_risk_pct: 0.05 } }
      )
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('per_trade_risk_exceeded') }
  end

  context 'when proposed trade would exceed exposure limit' do
    subject(:policy) do
      described_class.new(index_key: 'NIFTY', proposed_qty: 600, entry_price: 850.0)
    end

    let(:wallet_snapshot) { { equity: 500_000.0, exposure: 490_000.0 } }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('max_exposure_exceeded') }
  end

  context 'when daily loss limit is reached' do
    let(:daily_limit_result) { { allowed: false, reason: 'daily_loss_limit_reached' } }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('portfolio_drawdown_limit_reached') }
  end

  context 'when AlgoConfig raises' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'config error')
    end

    it 'does not raise' do
      expect { policy.permitted? }.not_to raise_error
    end
  end
end

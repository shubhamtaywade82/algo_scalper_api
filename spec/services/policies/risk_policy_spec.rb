# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Policies::RiskPolicy do
  subject(:policy) do
    described_class.new(
      index_key:    'NIFTY',
      proposed_qty: 50,
      entry_price:  250.0
    )
  end

  # ── Stub all external dependencies ─────────────────────────────────────────

  before do
    allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    allow(PositionTracker).to receive_message_chain(:active, :count).and_return(0)
    allow(AlgoConfig).to receive(:fetch).and_return(
      { risk: { max_active_positions: 3, max_exposure_pct: 0.30 } }
    )
    allow_any_instance_of(Live::DailyLimits).to receive(:can_trade?)
      .and_return({ allowed: true })

    wallet_double = { equity: 500_000.0, exposure: 50_000.0 }
    gateway_double = instance_double('Orders::GatewayPaper', wallet_snapshot: wallet_double)
    config_double  = double('Orders::Config', gateway: gateway_double)
    allow(Orders).to receive(:config).and_return(config_double)
  end

  # ── All clear ──────────────────────────────────────────────────────────────

  describe '#permitted? — all checks pass' do
    it { is_expected.to be_permitted }
    it { expect(policy.reasons).to be_empty }
  end

  # ── Circuit breaker ────────────────────────────────────────────────────────

  context 'when circuit breaker is tripped' do
    before { allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(true) }

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('circuit_breaker_tripped') }
  end

  # ── Max active positions ────────────────────────────────────────────────────

  context 'when max active positions are open' do
    before do
      allow(PositionTracker).to receive_message_chain(:active, :count).and_return(3)
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('max_active_positions_exceeded') }
  end

  # ── Max exposure ────────────────────────────────────────────────────────────

  context 'when proposed trade would exceed exposure limit' do
    subject(:policy) do
      # 50 * 250 = 12,500 notional; existing 490,000 + 12,500 > 30% of 500,000
      described_class.new(index_key: 'NIFTY', proposed_qty: 600, entry_price: 850.0)
    end

    before do
      wallet_double = { equity: 500_000.0, exposure: 490_000.0 }
      gateway_double = instance_double('Orders::GatewayPaper', wallet_snapshot: wallet_double)
      config_double  = double('Orders::Config', gateway: gateway_double)
      allow(Orders).to receive(:config).and_return(config_double)
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('max_exposure_exceeded') }
  end

  # ── Daily drawdown ──────────────────────────────────────────────────────────

  context 'when daily loss limit is reached' do
    before do
      allow_any_instance_of(Live::DailyLimits).to receive(:can_trade?)
        .and_return({ allowed: false, reason: 'daily_loss_limit_reached' })
    end

    it { is_expected.to be_forbidden }
    it { expect(policy.reasons).to include('portfolio_drawdown_limit_reached') }
  end

  # ── External failures fail gracefully ──────────────────────────────────────

  context 'when AlgoConfig raises' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'config error')
    end

    it 'does not raise' do
      expect { policy.permitted? }.not_to raise_error
    end
  end
end

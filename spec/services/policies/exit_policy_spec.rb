# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Policies::ExitPolicy do
  subject(:policy) { described_class.new(tracker: tracker) }

  let(:tracker) { build_stubbed(:position_tracker, status: 'active', order_no: 'ORD010') }

  # ── No exit condition ───────────────────────────────────────────────────────

  describe '#permitted? — no exit needed' do
    before do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(nil)
    end

    it { is_expected.not_to be_permitted }
    it { expect(policy.reasons).to be_empty }
    it { expect(policy.exit_reason).to be_nil }
    it { expect(policy.exit_path).to be_nil }
  end

  # ── Stop loss triggered ─────────────────────────────────────────────────────

  describe '#permitted? — stop loss triggered' do
    before do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(
        { exit: true, reason: 'STOP_LOSS', path: 'stop_loss', pnl_pct: -12.5 }
      )
    end

    it { is_expected.to be_permitted }
    it { expect(policy.reasons).to eq(['STOP_LOSS']) }
    it { expect(policy.exit_reason).to eq('STOP_LOSS') }
    it { expect(policy.exit_path).to eq('stop_loss') }
    it { expect(policy.pnl_pct).to eq(-12.5) }
  end

  # ── Take profit triggered ───────────────────────────────────────────────────

  describe '#permitted? — take profit' do
    before do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(
        { exit: true, reason: 'TAKE_PROFIT', path: 'take_profit', pnl_pct: 52.0 }
      )
    end

    it { is_expected.to be_permitted }
    it { expect(policy.exit_reason).to eq('TAKE_PROFIT') }
  end

  # ── Checker exception ───────────────────────────────────────────────────────

  describe '#permitted? — checker raises' do
    before do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions)
        .and_raise(StandardError, 'redis down')
    end

    it 'fails safe (no exit)' do
      expect(policy).not_to be_permitted
    end
  end

  # ── forbidden? is the inverse ──────────────────────────────────────────────

  describe '#forbidden?' do
    before do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(nil)
    end

    it { is_expected.to be_forbidden }
  end
end

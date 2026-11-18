# frozen_string_literal: true

require 'rails_helper'

# Pins WHICH exit wins when several conditions hold at once. The per-condition behaviour is covered in
# unified_exit_checker_spec.rb; the order of the waterfall was not covered anywhere, and it decides the
# exit reason, the exit path and therefore what is booked and alerted on.
RSpec.describe Live::UnifiedExitChecker, '.check_exit_conditions' do
  describe 'priority order' do
    subject(:decision) { described_class.check_exit_conditions(tracker) }

    let(:tracker) { instance_double(PositionTracker, id: 7, short_position?: false) }
    let(:snapshot) { { pnl_pct: 0.0345, timestamp: Time.current.to_i } }

    # Every exit step in the order the waterfall must evaluate them: what to stub so the step fires, and the
    # decision it must produce. Steps that return a result hash are quiet as nil; the rest are quiet as false.
    let(:steps) do
      [
        { stub: :emergency_peak_loss_exit_triggered?, fires: true,
          expected: { reason: 'EMERGENCY_PEAK_LOSS', path: 'emergency_peak_loss' } },
        { stub: :check_structure_invalidation, fires: { exit: true, reason: 'STRUCTURE_BREAK' },
          expected: { reason: 'STRUCTURE_BREAK', path: 'structure_invalidation' } },
        { stub: :smc_navigator_exit_hit?, fires: true,
          expected: { reason: 'SMC_NAVIGATOR_EXIT', path: 'smc_navigator' } },
        { stub: :loss_limit_hit?, fires: true,
          expected: { reason: 'STOP_LOSS', path: 'stop_loss' } },
        { stub: :percentage_pnl_exit_hit?, fires: true,
          expected: { reason: 'PERCENTAGE_PNL_EXIT', path: 'percentage_pnl_exit' } },
        { stub: :profit_target_hit?, fires: true,
          expected: { reason: 'TAKE_PROFIT', path: 'take_profit' } },
        { stub: :early_exit_triggered?, fires: true,
          expected: { reason: 'EARLY_TREND_FAILURE', path: 'early_exit' } },
        { stub: :premium_momentum_failure_hit?, fires: true,
          expected: { reason: 'PREMIUM_MOMENTUM_FAILURE', path: 'premium_momentum_failure' } },
        { stub: :evaluate_trailing_stop, fires: { exit: true, reason: 'TRAILING_STOP', path: 'trailing_stop' },
          expected: { reason: 'TRAILING_STOP', path: 'trailing_stop' } },
        { stub: :time_based_exit?, fires: true,
          expected: { reason: 'TIME_BASED', path: 'time_based_exit' } }
      ]
    end

    def fire(steps)
      steps.each { |step| allow(described_class).to receive(step[:stub]).and_return(step[:fires]) }
    end

    before do
      allow(described_class).to receive_messages(pnl_snapshot: snapshot, portfolio_floor_breach?: false)
      steps.each { |step| allow(described_class).to receive(step[:stub]).and_return(step[:fires].is_a?(Hash) ? nil : false) }
    end

    it 'returns nil when no exit condition holds' do
      expect(decision).to be_nil
    end

    %w[EMERGENCY_PEAK_LOSS STRUCTURE_BREAK SMC_NAVIGATOR_EXIT STOP_LOSS PERCENTAGE_PNL_EXIT
       TAKE_PROFIT EARLY_TREND_FAILURE PREMIUM_MOMENTUM_FAILURE TRAILING_STOP TIME_BASED].each_with_index do |reason, index|
      it "lets #{reason} win over every step after it" do
        fire(steps.drop(index))

        expect(decision).to include(exit: true, **steps[index][:expected])
      end
    end

    it 'reports the position pnl percentage on the decision' do
      allow(described_class).to receive(:time_based_exit?).and_return(true)

      expect(decision[:pnl_pct]).to eq(3.45)
    end

    it 'lets the portfolio floor override everything, even a missing snapshot' do
      allow(described_class).to receive_messages(portfolio_floor_breach?: true, pnl_snapshot: nil)
      fire(steps)

      expect(decision).to eq(exit: true, reason: 'PORTFOLIO_FLOOR_BREACH', path: 'profit_lock', pnl_pct: nil)
    end

    it 'falls back to the stop-loss-only check, skipping every other step, when the snapshot is missing' do
      allow(described_class).to receive_messages(pnl_snapshot: nil, blind_spot_fallback_check: { exit: true, reason: 'STOP_LOSS_SNAPSHOT_FALLBACK' })
      fire(steps)

      expect(decision).to eq(exit: true, reason: 'STOP_LOSS_SNAPSHOT_FALLBACK')
    end

    it 'runs none of the long-only steps for a short position' do
      allow(tracker).to receive(:short_position?).and_return(true)
      fire(steps)

      expect(decision).to be_nil
    end
  end
end

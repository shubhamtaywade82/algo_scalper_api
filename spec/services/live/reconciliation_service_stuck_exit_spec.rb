# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ReconciliationService do
  let(:service) { described_class.instance }
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      order_no: 'ORD123',
      active?: true,
      exit_requested_at: 1.minute.ago,
      exit_reason: nil
    )
  end

  before do
    allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
    service.instance_variable_get(:@exit_attempts)&.clear
    service.instance_variable_get(:@exit_cooldowns)&.clear
  end

  describe '#stuck_in_exit?' do
    it 'is true when exit was requested more than 30s ago and still active' do
      expect(service.send(:stuck_in_exit?, tracker)).to be true
    end

    it 'is false when not active' do
      inactive = instance_double(PositionTracker, active?: false)
      expect(service.send(:stuck_in_exit?, inactive)).to be false
    end
  end

  describe '#fix_stuck_exit' do
    context 'when an exit_engine reference is available' do
      it 'retries the exit via the real ExitEngine (broker-confirmed path)' do
        exit_engine = instance_double(Live::ExitEngine, execute_exit: { success: true })
        supervisor = { exit_manager: exit_engine }
        allow(Rails.application.config.x).to receive(:trading_supervisor).and_return(supervisor)

        service.send(:fix_stuck_exit, tracker)

        expect(exit_engine).to have_received(:execute_exit).with(tracker, 'AUTO_RECONCILED_EXIT')
        expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_error)
      end

      it 'retries the exit when trading_supervisor is a TradingSystem::Supervisor instance' do
        exit_engine = instance_double(Live::ExitEngine, execute_exit: { success: true })
        supervisor = TradingSystem::Supervisor.new
        supervisor.register(:exit_manager, exit_engine)
        allow(Rails.application.config.x).to receive(:trading_supervisor).and_return(supervisor)

        service.send(:fix_stuck_exit, tracker)

        expect(exit_engine).to have_received(:execute_exit).with(tracker, 'AUTO_RECONCILED_EXIT')
        expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_error)
      end
    end

    context 'when cooldown is active' do
      it 'skips exit execution during cooldown' do
        exit_engine = instance_double(Live::ExitEngine, execute_exit: { success: true })
        supervisor = { exit_manager: exit_engine }
        allow(Rails.application.config.x).to receive(:trading_supervisor).and_return(supervisor)

        # First call triggers exit and sets cooldown
        service.send(:fix_stuck_exit, tracker)
        expect(exit_engine).to have_received(:execute_exit).once

        # Second call during cooldown should skip exit
        service.send(:fix_stuck_exit, tracker)
        expect(exit_engine).to have_received(:execute_exit).once
      end
    end

    context 'when max exit attempts are exceeded' do
      it 'escalates error and halts further auto-exit attempts' do
        exit_engine = instance_double(Live::ExitEngine, execute_exit: { success: true })
        supervisor = { exit_manager: exit_engine }
        allow(Rails.application.config.x).to receive(:trading_supervisor).and_return(supervisor)

        # Force attempts key to exceed MAX_RECONCILE_EXIT_ATTEMPTS
        service.instance_variable_get(:@exit_attempts)[tracker.id] = 3

        service.send(:fix_stuck_exit, tracker)

        expect(exit_engine).not_to have_received(:execute_exit)
        expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
          a_string_matching(/Exceeded max exit attempts/),
          context: 'Live::ReconciliationService#fix_stuck_exit'
        )
      end
    end

    context 'when no exit_engine reference is available' do
      it 'does NOT mark the tracker exited and escalates instead' do
        allow(Rails.application.config.x).to receive(:trading_supervisor).and_return(nil)
        allow(tracker).to receive(:mark_exited!)

        service.send(:fix_stuck_exit, tracker)

        expect(tracker).not_to have_received(:mark_exited!)
        expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
          a_string_matching(/CANNOT confirm broker fill/),
          context: 'Live::ReconciliationService#fix_stuck_exit'
        )
      end
    end
  end
end

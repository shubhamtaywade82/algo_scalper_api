# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Daemon do
  describe '#check_service_health!' do
    let(:supervisor) { instance_double(TradingSystem::Supervisor) }
    let(:daemon) { described_class.new(supervisor: supervisor) }

    before do
      allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
    end

    it 'restarts and alerts for each unhealthy service' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: false, signal_scheduler: true)
      allow(supervisor).to receive(:restart_service)

      daemon.send(:check_service_health!)

      expect(supervisor).to have_received(:restart_service).with(:risk_manager).once
      expect(supervisor).not_to have_received(:restart_service).with(:signal_scheduler)
      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
        a_string_matching(/risk_manager/),
        context: 'TradingSystem::Daemon#check_service_health!'
      )
    end

    it 'does nothing when all services are healthy' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: true)
      allow(supervisor).to receive(:restart_service)

      daemon.send(:check_service_health!)

      expect(supervisor).not_to have_received(:restart_service)
      expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_error)
    end

    it 'does not raise if restart_service itself fails' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: false)
      allow(supervisor).to receive(:restart_service).and_raise('restart failed')

      expect { daemon.send(:check_service_health!) }.not_to raise_error
    end

    it 'is a no-op when there is no supervisor' do
      daemon_without_supervisor = described_class.new(supervisor: nil)
      expect { daemon_without_supervisor.send(:check_service_health!) }.not_to raise_error
    end
  end
end

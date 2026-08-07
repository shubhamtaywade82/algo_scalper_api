# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Supervisor do
  let(:supervisor) { described_class.new }

  describe '#health_check' do
    it 'is a public method' do
      expect(supervisor.public_methods(false)).to include(:health_check)
    end

    it 'reports true for a service with no health method' do
      supervisor.register(:no_health, Object.new)
      expect(supervisor.health_check).to eq(no_health: true)
    end

    it 'reports healthy? result when the service defines it' do
      healthy_service = double('Service', healthy?: false)
      supervisor.register(:flaky, healthy_service)
      expect(supervisor.health_check).to eq(flaky: false)
    end

    it 'reports running? result when the service defines it but not healthy?' do
      running_service = double('Service', running?: false)
      supervisor.register(:stopped, running_service)
      expect(supervisor.health_check).to eq(stopped: false)
    end

    it 'reports false if the health check itself raises' do
      broken_service = double('Service')
      allow(broken_service).to receive(:healthy?).and_raise('boom')
      supervisor.register(:broken, broken_service)
      expect(supervisor.health_check).to eq(broken: false)
    end
  end

  describe '#start_all / #stop_all audit logging' do
    let(:service) { double('Service', start: true, stop: true) } # rubocop:disable RSpec/VerifiedDoubles

    before { supervisor.register(:svc, service) }

    it 'creates a bot_start audit log entry on start_all' do
      expect { supervisor.start_all }.to change(AuditLog, :count).by(1)
      expect(AuditLog.last.event_type).to eq('bot_start')
    end

    it 'does not double-log when start_all is called again while already running' do
      supervisor.start_all
      expect { supervisor.start_all }.not_to change(AuditLog, :count)
    end

    it 'creates a bot_stop audit log entry on stop_all' do
      supervisor.start_all
      expect { supervisor.stop_all }.to change(AuditLog, :count).by(1)
      expect(AuditLog.last.event_type).to eq('bot_stop')
    end

    it 'does not log stop_all when not running' do
      expect { supervisor.stop_all }.not_to change(AuditLog, :count)
    end
  end
end

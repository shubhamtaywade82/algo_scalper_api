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
end

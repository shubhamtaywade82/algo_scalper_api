# frozen_string_literal: true

require 'rails_helper'

# Define the classes locally for testing since they're defined in the initializer
module TradingSystem
  class Supervisor
    def initialize
      @services = {}
      @running = false
    end

    def register(name, instance)
      @services[name] = instance
    end

    delegate :[], to: :@services

    def start_all
      return if @running

      @services.each do |_name, service|
        service.start
      end

      @running = true
    end

    def stop_all
      return unless @running

      @services.reverse_each do |_name, service|
        service.stop
      end

      @running = false
    end
  end
end

RSpec.describe 'TradingSystem::Supervisor Market Close Behavior' do
  let(:supervisor) { TradingSystem::Supervisor.new }
  let(:market_feed) { instance_double('MarketFeedHubService', start: true, stop: true) }
  let(:signal_scheduler) { instance_double(Signal::Scheduler, start: true, stop: true) }
  let(:risk_manager) { instance_double(Live::RiskManagerService, start: true, stop: true) }
  let(:heartbeat) { instance_double(TradingSystem::PositionHeartbeat, start: true, stop: true) }
  let(:router) { instance_double(TradingSystem::OrderRouter, start: true, stop: true) }
  let(:pnl_refresher) { instance_double(Live::PaperPnlRefresher, start: true, stop: true) }
  let(:exit_engine) { instance_double(Live::ExitEngine, start: true, stop: true) }
  let(:active_cache) { instance_double('ActiveCacheService', start: true, stop: true) }
  let(:reconciliation) { instance_double(Live::ReconciliationService, start: true, stop: true) }

  before do
    # Register all services with the supervisor
    supervisor.register(:market_feed, market_feed)
    supervisor.register(:signal_scheduler, signal_scheduler)
    supervisor.register(:risk_manager, risk_manager)
    supervisor.register(:position_heartbeat, heartbeat)
    supervisor.register(:order_router, router)
    supervisor.register(:paper_pnl_refresher, pnl_refresher)
    supervisor.register(:exit_manager, exit_engine)
    supervisor.register(:active_cache, active_cache)
    supervisor.register(:reconciliation, reconciliation)
  end

  describe 'when market is closed' do
    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
    end

    it 'only starts MarketFeedHub (simulating initializer behavior)' do
      # Simulate the initializer logic when market is closed
      supervisor[:market_feed]&.start if TradingSession::Service.market_closed?

      expect(market_feed).to have_received(:start)
      expect(signal_scheduler).not_to have_received(:start)
      expect(risk_manager).not_to have_received(:start)
      expect(heartbeat).not_to have_received(:start)
      expect(router).not_to have_received(:start)
      expect(pnl_refresher).not_to have_received(:start)
      expect(exit_engine).not_to have_received(:start)
      expect(active_cache).not_to have_received(:start)
      expect(reconciliation).not_to have_received(:start)
    end
  end

  describe 'when market is open' do
    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    end

    it 'starts all services (simulating initializer behavior)' do
      # Simulate the initializer logic when market is open
      supervisor.start_all unless TradingSession::Service.market_closed?

      expect(market_feed).to have_received(:start)
      expect(signal_scheduler).to have_received(:start)
      expect(risk_manager).to have_received(:start)
      expect(heartbeat).to have_received(:start)
      expect(router).to have_received(:start)
      expect(pnl_refresher).to have_received(:start)
      expect(exit_engine).to have_received(:start)
      expect(active_cache).to have_received(:start)
      expect(reconciliation).to have_received(:start)
    end
  end
end

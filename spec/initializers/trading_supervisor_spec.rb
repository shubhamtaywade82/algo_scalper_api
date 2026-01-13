# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Daemon do
  let(:supervisor) { TradingSystem::Supervisor.new }
  let(:market_feed) { instance_double(Live::MarketFeedHubService, start: true, stop: true, subscribe_many: true) }
  let(:signal_scheduler) { instance_double(Signal::Scheduler, start: true, stop: true) }
  let(:risk_manager) { instance_double(Live::RiskManagerService, start: true, stop: true) }
  let(:heartbeat) { instance_double(TradingSystem::PositionHeartbeat, start: true, stop: true) }
  let(:router) { instance_double(TradingSystem::OrderRouter, start: true, stop: true) }
  let(:pnl_refresher) { instance_double(Live::PaperPnlRefresher, start: true, stop: true) }
  let(:exit_engine) { instance_double(Live::ExitEngine, start: true, stop: true) }
  let(:active_cache) { instance_double(ActiveCacheService, start: true, stop: true) }
  let(:reconciliation) { instance_double(Live::ReconciliationService, start: true, stop: true) }

  before do
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

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ENABLE_TRADING_SERVICES').and_return('true')
    allow(ENV).to receive(:[]).with('DISABLE_TRADING_SERVICES').and_return(nil)
    allow(ENV).to receive(:[]).with('BACKTEST_MODE').and_return(nil)
    allow(ENV).to receive(:[]).with('SCRIPT_MODE').and_return(nil)
  end

  describe 'when market is closed' do
    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
    end

    it 'only starts WebSocket service' do
      described_class.new(supervisor: supervisor).start(keep_alive: false, allow_in_test: true)

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
      allow(Live::PositionIndex).to receive_message_chain(:instance, :all_keys).and_return([])
    end

    it 'starts all services' do
      described_class.new(supervisor: supervisor).start(keep_alive: false, allow_in_test: true)

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

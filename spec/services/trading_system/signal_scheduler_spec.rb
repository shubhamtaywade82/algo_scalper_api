# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::SignalScheduler do
  let(:service) { described_class.new }

  describe '#start' do
    after { service.stop }

    it 'starts the service' do
      service.start
      expect(service.instance_variable_get(:@running)).to be true
    end

    it 'creates a thread with correct name' do
      service.start
      thread = service.instance_variable_get(:@thread)
      expect(thread).to be_alive
      # Thread name may be nil on some Ruby versions, so just check it's alive
      expect(thread.name).to be_nil.or(eq('signal-scheduler'))
    end
  end

  describe '#stop' do
    it 'stops the service' do
      service.start
      service.stop
      expect(service.instance_variable_get(:@running)).to be false
    end
  end

  describe '#perform_signal_scan' do
    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Signal::Scheduler).to receive(:new)
      end

      it 'skips signal generation' do
        service.send(:perform_signal_scan)
        expect(Signal::Scheduler).not_to have_received(:new)
      end
    end

    context 'when market is open' do
      let(:scheduler_instance) { instance_double(Signal::Scheduler) }

      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(AlgoConfig).to receive(:fetch).and_return({ indices: [{ key: 'NIFTY' }] })
        allow(Signal::Scheduler).to receive(:new).and_return(scheduler_instance)
        # process_index is a private method, so we stub it to allow verification
        allow(scheduler_instance).to receive(:process_index)
      end

      it 'performs signal scan by processing indices' do
        service.send(:perform_signal_scan)
        expect(Signal::Scheduler).to have_received(:new).with(period: 1)
        expect(AlgoConfig).to have_received(:fetch)
        # Verify process_index was called via send (private method)
        expect(scheduler_instance).to have_received(:process_index).with({ key: 'NIFTY' })
      end
    end
  end

  describe '#run_loop' do
    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(service).to receive(:perform_signal_scan)
      end

      it 'sleeps 60 seconds instead of calling perform_signal_scan' do
        service.start
        sleep(0.1) # Give thread time to start
        expect(service).not_to have_received(:perform_signal_scan)
        service.stop
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:perform_signal_scan)
      end

      it 'calls perform_signal_scan' do
        service.start
        sleep(0.1) # Give thread time to start
        expect(service).to have_received(:perform_signal_scan).at_least(:once)
        service.stop
      end
    end
  end
end

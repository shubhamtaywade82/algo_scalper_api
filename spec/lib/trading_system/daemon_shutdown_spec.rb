# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Daemon do
  describe '#safe_stop!' do
    let(:supervisor) { instance_double(TradingSystem::Supervisor, stop_all: true) }
    let(:daemon) { described_class.new(supervisor: supervisor) }

    before do
      allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
    end

    it 'alerts with the open-position count before stopping services' do
      allow(PositionTracker).to receive_message_chain(:active, :count).and_return(3)

      daemon.send(:safe_stop!)

      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
        a_string_matching(/3 open position\(s\).*UNMONITORED/),
        context: 'TradingSystem::Daemon#safe_stop!'
      )
      expect(supervisor).to have_received(:stop_all)
    end

    it 'does not alert when there are no open positions' do
      allow(PositionTracker).to receive_message_chain(:active, :count).and_return(0)

      daemon.send(:safe_stop!)

      expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_error)
      expect(supervisor).to have_received(:stop_all)
    end
  end

  describe '#enqueue_instruments_import_if_stale!' do
    let(:daemon) { described_class.new(supervisor: instance_double(TradingSystem::Supervisor)) }

    it 'enqueues an import when the master was last imported days ago' do
      allow(Setting).to receive(:fetch).with('instruments.last_imported_at').and_return(3.days.ago.iso8601)

      expect { daemon.send(:enqueue_instruments_import_if_stale!) }
        .to have_enqueued_job(InstrumentsImportJob)
    end

    it 'skips the import when the master is fresh' do
      allow(Setting).to receive(:fetch).with('instruments.last_imported_at').and_return(1.hour.ago.iso8601)

      expect { daemon.send(:enqueue_instruments_import_if_stale!) }
        .not_to have_enqueued_job(InstrumentsImportJob)
    end
  end
end

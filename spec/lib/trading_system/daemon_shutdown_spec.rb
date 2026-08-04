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
end

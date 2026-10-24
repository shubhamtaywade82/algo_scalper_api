# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PortfolioResetJob do
  describe '#perform' do
    it 'calls Portfolio::DrawdownGuard.reset_day!' do
      allow(Portfolio::DrawdownGuard).to receive(:reset_day!)
      described_class.new.perform
      expect(Portfolio::DrawdownGuard).to have_received(:reset_day!)
    end

    it 'rescues errors and notifies telegram' do
      notifier = instance_double(Notifications::TelegramNotifier)
      allow(notifier).to receive(:notify_error)
      allow(Notifications::TelegramNotifier).to receive(:instance).and_return(notifier)
      allow(Portfolio::DrawdownGuard).to receive(:reset_day!).and_raise(StandardError, 'Redis connection lost')

      expect { described_class.new.perform }.not_to raise_error
      expect(notifier).to have_received(:notify_error).with('StandardError - Redis connection lost', context: 'PortfolioResetJob')
    end
  end
end

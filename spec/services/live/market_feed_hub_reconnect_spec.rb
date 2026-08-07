# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  describe '#handle_reconnect' do
    it 'resubscribes active positions immediately on a gem-reported reconnect' do
      hub = described_class.instance
      allow(hub).to receive(:resubscribe_active_positions_after_reconnect)

      hub.send(:handle_reconnect, { attempt: 2, resubscribed: false })

      expect(hub).to have_received(:resubscribe_active_positions_after_reconnect)
    end
  end

  describe '#restart!' do
    let(:hub) { described_class.instance }

    before do
      allow(hub).to receive(:running?).and_return(true)
      allow(hub).to receive(:stop!)
      allow(hub).to receive(:start!)
      allow(hub).to receive(:sleep)
      hub.instance_variable_set(:@reconnect_attempts, 0)
      hub.instance_variable_set(:@restarting, false)
    end

    it 'applies exponential backoff on consecutive restart calls' do
      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(2)

      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(4)

      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(8)
    end

    it 'resets reconnect attempts when update_connection_state! is called' do
      hub.send(:restart!)
      hub.send(:update_connection_state!)
      expect(hub.instance_variable_get(:@reconnect_attempts)).to eq(0)
    end
  end
end

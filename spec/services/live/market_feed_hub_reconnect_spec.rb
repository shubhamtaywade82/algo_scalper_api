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
end

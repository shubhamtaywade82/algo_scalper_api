# frozen_string_literal: true

require 'spec_helper'
require 'redis'
require 'active_support/all'
require_relative '../../../app/services/dhan/sidecar_publisher'

RSpec.describe Dhan::SidecarPublisher do
  describe '.publish_intent' do
    it 'publishes execution intent payload to Redis dhan:execution:intents channel' do
      mock_redis = instance_double(Redis)
      allow(Redis).to receive(:new).and_return(mock_redis)
      allow(mock_redis).to receive(:publish).and_return(1)

      result = described_class.publish_intent(
        strategy: 'bull_call_spread',
        params: { symbol: 'NIFTY', strike: 24_500, quantity: 50 },
        correlation_id: 'CORR_123',
        risk_limits: { stop_loss: 100 }
      )

      expect(result).to eq(1)
      expect(mock_redis).to have_received(:publish).with(
        'dhan:execution:intents',
        anything
      )
    end
  end
end

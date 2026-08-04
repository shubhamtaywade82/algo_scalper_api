# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::CacheBroadcaster do
  describe '.publish!' do
    it 'publishes invalidation without raising when redis is available' do
      redis = instance_double(Redis, publish: 1)
      allow(described_class).to receive_messages(enabled?: true, redis: redis)

      expect { described_class.publish!(source: 'spec') }.not_to raise_error
      expect(redis).to have_received(:publish).with('algo_config:invalidate', kind_of(String))
    end
  end
end

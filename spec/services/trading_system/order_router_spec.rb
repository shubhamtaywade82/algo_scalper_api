# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::OrderRouter do
  let(:gateway) { instance_double(Orders::GatewayLive) }
  let(:router) { described_class.new(gateway: gateway) }
  let(:tracker) { instance_double(PositionTracker, order_no: 'ORD123') }

  before { allow(router).to receive(:sleep) }

  describe '#exit_market' do
    it 'returns the gateway result on success without retrying' do
      allow(gateway).to receive(:exit_market)
        .with(tracker, client_order_id: 'COID-1')
        .and_return({ success: true, order_id: 'X' })

      result = router.exit_market(tracker, client_order_id: 'COID-1')

      expect(result).to eq({ success: true, order_id: 'X' })
      expect(gateway).to have_received(:exit_market).once
    end

    it 'retries a retryable (network/timeout) error and succeeds on a later attempt' do
      attempts = 0
      allow(gateway).to receive(:exit_market) do
        attempts += 1
        raise Timeout::Error, 'timed out' if attempts < 3

        { success: true, order_id: 'X' }
      end

      result = router.exit_market(tracker, client_order_id: 'COID-1')

      expect(result).to eq({ success: true, order_id: 'X' })
      expect(attempts).to eq(3)
    end

    it 'reuses the same client_order_id across every retry attempt (regression: a fresh ' \
       'random id per retry would defeat the broker\'s correlation-id dedup)' do
      seen_coids = []
      allow(gateway).to receive(:exit_market) do |_tracker, client_order_id:|
        seen_coids << client_order_id
        raise Timeout::Error, 'timed out' if seen_coids.size < 3

        { success: true, order_id: 'X' }
      end

      router.exit_market(tracker, client_order_id: 'COID-STABLE')

      expect(seen_coids).to eq(%w[COID-STABLE COID-STABLE COID-STABLE])
    end

    it 'gives up after RETRY_COUNT attempts and returns a failure hash, not an exception' do
      allow(gateway).to receive(:exit_market).and_raise(Timeout::Error, 'timed out')

      result = router.exit_market(tracker, client_order_id: 'COID-1')

      expect(result).to include(success: false)
      expect(gateway).to have_received(:exit_market).exactly(described_class::RETRY_COUNT).times
    end

    it 'does not retry a non-retryable (definitive rejection) error' do
      allow(gateway).to receive(:exit_market).and_raise(DhanHQ::OrderError, 'insufficient margin')

      result = router.exit_market(tracker, client_order_id: 'COID-1')

      expect(result).to include(success: false, error: a_string_matching(/insufficient margin/))
      expect(gateway).to have_received(:exit_market).once
    end
  end

  describe '#retryable?' do
    it 'treats Timeout::Error, SocketError, ECONNREFUSED and ETIMEDOUT as retryable' do
      [Timeout::Error.new, SocketError.new, Errno::ECONNREFUSED.new, Errno::ETIMEDOUT.new].each do |error|
        expect(router.send(:retryable?, error)).to be true
      end
    end

    it 'treats an ordinary broker/business error as not retryable' do
      expect(router.send(:retryable?, StandardError.new('bad request'))).to be false
    end
  end
end

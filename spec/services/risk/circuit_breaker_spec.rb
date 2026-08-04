# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::CircuitBreaker do
  let(:cb) { described_class.instance }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
    cb.reset!
  end

  after { cb.reset! }

  describe '#trip!' do
    it 'broadcasts circuit_breaker status to the dashboard channel' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'dashboard',
        hash_including(type: 'circuit_breaker', tripped: true)
      )
      cb.trip!(reason: 'test halt')
    end
  end

  describe '#reset!' do
    before { cb.trip!(reason: 'setup') }

    it 'broadcasts circuit_breaker status to the dashboard channel' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'dashboard',
        hash_including(type: 'circuit_breaker', tripped: false)
      )
      cb.reset!
    end
  end

  describe '#tripped?' do
    context 'when cache read fails' do
      before do
        allow(Rails.cache).to receive(:read).and_raise(Redis::BaseError, 'connection refused')
        allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
      end

      it 'fails CLOSED (returns true, blocking entries)' do
        expect(cb.tripped?).to be true
      end

      it 'alerts via Telegram' do
        cb.tripped?
        expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
          a_string_matching(/failing CLOSED/),
          context: 'CircuitBreaker#tripped?'
        )
      end
    end

    context 'when cache is healthy and not tripped' do
      it 'returns false' do
        expect(cb.tripped?).to be false
      end
    end
  end
end

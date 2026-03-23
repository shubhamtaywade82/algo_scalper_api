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
    cb.reset! rescue nil
  end

  after { cb.reset! rescue nil }

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
end

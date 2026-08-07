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

    it 'creates a kill_switch_trip audit log entry' do
      expect { cb.trip!(reason: 'test halt') }.to change(AuditLog, :count).by(1)
      expect(AuditLog.last).to have_attributes(event_type: 'kill_switch_trip')
      expect(AuditLog.last.metadata['reason']).to eq('test halt')
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

    it 'creates a kill_switch_reset audit log entry' do
      expect { cb.reset! }.to change(AuditLog, :count).by(1)
      expect(AuditLog.last).to have_attributes(event_type: 'kill_switch_reset')
    end
  end

  describe '#force_close_all!' do
    let(:exit_engine) { instance_double(Live::ExitEngine, execute_exit: true) }

    it 'creates a square_off audit log entry with the position count' do
      expect { cb.force_close_all!(exit_engine: exit_engine, reason: 'manual halt') }
        .to change(AuditLog, :count).by(1)
      expect(AuditLog.last).to have_attributes(event_type: 'square_off')
      expect(AuditLog.last.metadata['reason']).to eq('manual halt')
    end
  end
end

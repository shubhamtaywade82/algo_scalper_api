# frozen_string_literal: true

require 'securerandom'

module EventStore
  class DecisionTrace
    THREAD_KEY = :current_decision_trace

    attr_reader :decision_id, :started_at, :index_key, :direction, :metadata, :status

    def initialize(index_key:, direction:, metadata: {})
      @decision_id = SecureRandom.uuid
      @started_at = Time.current
      @index_key = index_key
      @direction = direction
      @metadata = metadata.freeze
      @status = :initiated
    end

    def self.with_trace(index_key:, direction:, metadata: {})
      trace = new(index_key: index_key, direction: direction, metadata: metadata)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = trace
      yield trace
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def self.current
      Thread.current[THREAD_KEY]
    end

    def self.current_id
      current&.decision_id
    end

    def mark_status(new_status)
      @status = new_status
    end

    def to_h
      {
        decision_id: decision_id,
        started_at: started_at.iso8601(3),
        index_key: index_key,
        direction: direction,
        status: status,
        metadata: metadata
      }
    end
  end
end

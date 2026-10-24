# frozen_string_literal: true

module EventStore
  # Deterministic replay of persisted events (primarily for audit / future backtest adapters).
  class ReplayEngine
    def initialize(stream:, from:, to:)
      @events = SmcEvent.where(stream: stream).where(created_at: from..to).order(:created_at, :sequence)
    end

    def each_event(&)
      @events.find_each(&)
    end

    delegate :to_a, to: :@events
  end
end

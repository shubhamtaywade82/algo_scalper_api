# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.6 "Execution Agent" — at Level 1 (Advisor) this only
    # measures execution quality from the FSM audit trail every
    # PositionTracker already carries (Orders::Fsm writes meta['fsm_history']
    # on every transition); it does not choose order types, time entries, or
    # touch EntryGuardPipeline/ExitEngine. The report's "optimal entry
    # timing"/"adaptive limit pricing" capabilities are Level 2 work, out of
    # scope here.
    class ExecutionAgent < BaseAgent
      DEFAULT_SAMPLE_SIZE = 50
      MIN_SAMPLE_FOR_CONFIDENCE = 20
      FILL_START_STATES = %w[submitting created].freeze
      FILL_END_STATES = %w[filled acknowledged].freeze

      private

      def perform(sample_size: DEFAULT_SAMPLE_SIZE)
        trackers = PositionTracker.where.not(meta: {}).order(created_at: :desc).limit(sample_size)
        latencies = trackers.filter_map { |t| fill_latency_seconds(t) }

        if latencies.empty?
          return { decision_type: 'execution_quality', confidence: 0.0,
                   output: { sample_size: 0, note: 'no FSM history available yet' } }
        end

        sorted = latencies.sort
        avg = (sorted.sum / sorted.size).round(3)
        p95 = sorted[(sorted.size * 0.95).ceil - 1]

        {
          decision_type: 'execution_quality',
          confidence: [latencies.size.to_f / MIN_SAMPLE_FOR_CONFIDENCE, 1.0].min.round(4),
          output: {
            sample_size: latencies.size,
            avg_fill_latency_seconds: avg,
            p95_fill_latency_seconds: p95
          }
        }
      end

      def fill_latency_seconds(tracker)
        history = Array(tracker.meta['fsm_history'])
        return nil if history.empty?

        start_event = history.find { |h| FILL_START_STATES.include?(h['to_state']) }
        end_event = history.find { |h| FILL_END_STATES.include?(h['to_state']) }
        return nil unless start_event && end_event

        Time.iso8601(end_event['transitioned_at']) - Time.iso8601(start_event['transitioned_at'])
      rescue StandardError
        nil
      end
    end
  end
end

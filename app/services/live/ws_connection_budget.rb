# frozen_string_literal: true

module Live
  module WsConnectionBudget
    class Error < StandardError; end
    class BudgetExceeded < Error; end

    class << self
      def max_concurrent
        @max_concurrent ||= (ENV['WS_MAX_CONCURRENT'] || 5).to_i
      end

      def max_concurrent=(value)
        @max_concurrent = value.to_i
      end

      def active_ids
        @active_ids ||= Concurrent::Set.new
      end

      def lock
        @lock ||= Mutex.new
      end

      # Attempt to register a new connection.
      def acquire!(connection_id)
        raise ArgumentError, 'connection_id required' if connection_id.to_s.strip.empty?

        lock.synchronize do
          if active_ids.size >= max_concurrent
            Rails.logger.warn("[WsConnectionBudget] Connection budget exhausted (#{active_ids.size}/#{max_concurrent}). Rejecting new connection: #{connection_id}")
            raise BudgetExceeded, "max #{max_concurrent} concurrent WebSocket connections reached"
          end

          active_ids.add(connection_id.to_s)
          Rails.logger.debug("[WsConnectionBudget] Connection acquired #{connection_id} (#{active_ids.size}/#{max_concurrent})")
          true
        end
      end

      def release!(connection_id)
        raise ArgumentError, 'connection_id required' if connection_id.to_s.strip.empty?

        lock.synchronize do
          removed = active_ids.delete?(connection_id.to_s)
          Rails.logger.debug("[WsConnectionBudget] Connection released #{connection_id} (#{active_ids.size}/#{max_concurrent})")
          removed
        end
      end

      def status
        {
          max_concurrent: max_concurrent,
          active_count: lock.synchronize { active_ids.size },
          active_ids: lock.synchronize { active_ids.to_a }
        }
      end

      def exhausted?
        lock.synchronize { active_ids.size >= max_concurrent }
      end
    end
  end
end

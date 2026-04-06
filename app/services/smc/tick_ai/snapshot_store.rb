# frozen_string_literal: true

module Smc
  module TickAi
    # Persists last LTF alignment flags per index security_id for rising-edge detection.
    class SnapshotStore
      PREFIX = 'smc:tick_ai:prev'

      class << self
        def read(security_id)
          raw = RedisConnection.client.get("#{PREFIX}:#{security_id}")
          return {} if raw.blank?

          JSON.parse(raw)
        rescue JSON::ParserError, StandardError => e
          Rails.logger.warn("[Smc::TickAi::SnapshotStore] read failed: #{e.class} - #{e.message}")
          {}
        end

        def write(security_id, flags)
          RedisConnection.client.set("#{PREFIX}:#{security_id}", JSON.generate(flags))
        rescue StandardError => e
          Rails.logger.warn("[Smc::TickAi::SnapshotStore] write failed: #{e.class} - #{e.message}")
        end
      end
    end
  end
end

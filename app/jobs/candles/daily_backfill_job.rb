# frozen_string_literal: true

module Candles
  class DailyBackfillJob < ApplicationJob
    queue_as :background

    # NIFTY, BANKNIFTY, SENSEX DhanHQ index security IDs (matches IvSnapshotJob::INDEX_MAP)
    INDEX_SECURITY_IDS = %w[13 25 51].freeze

    def perform
      INDEX_SECURITY_IDS.each { |sid| Candles::BackfillJob.perform_later(security_id: sid) }
    end
  end
end

# frozen_string_literal: true

module Candles
  class RetentionJob < ApplicationJob
    queue_as :background

    RETENTION = 2.years

    def perform
      cutoff = RETENTION.ago
      Record.where(timeframe: "1m").where(Record.arel_table[:ts].lt(cutoff)).in_batches.delete_all
    end
  end
end

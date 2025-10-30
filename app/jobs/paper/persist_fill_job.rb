# frozen_string_literal: true

module Paper
  class PersistFillJob < ApplicationJob
    queue_as :default

    # Expected args:
    # trading_date:, exchange_segment:, security_id:, side:, qty:, price:,
    # charge:, gross_value:, net_value:, executed_at:, meta:
    def perform(**args)
      PaperFillsLog.create!(**args)
    end
  end
end



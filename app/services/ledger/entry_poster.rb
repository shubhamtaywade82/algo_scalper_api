# frozen_string_literal: true

module Ledger
  class EntryPoster
    class << self
      def post!(tracker:, fill_price:, quantity:, order_no: nil)
        return nil unless paper_posting?(tracker)
        return nil unless Config.posting_enabled_for_paper?

        Seeder.ensure_ready!

        qty = quantity.to_i
        price = BigDecimal(fill_price.to_s)
        gross = (qty * price).round(2)
        fee = BrokerFeeCalculator.fee_per_order

        PostingService.post!(
          idempotency_key: "entry:#{tracker.id}",
          event_type: 'entry_fill',
          mode: :paper,
          position_tracker_id: tracker.id,
          order_no: order_no || tracker.order_no,
          trading_date: Time.zone.today,
          meta: {
            symbol: tracker.symbol,
            security_id: tracker.security_id,
            gross_premium: gross.to_f,
            fee: fee.to_f,
            iv_percentile: tracker.iv_percentile
          }.compact,
          lines: [
            { account_code: 'premium_deployed', debit: gross },
            { account_code: 'cash', credit: gross },
            { account_code: 'brokerage_expense', debit: fee },
            { account_code: 'cash', credit: fee }
          ]
        )
      rescue PostingService::InsufficientCashError => e
        Rails.logger.warn("[Ledger::EntryPoster] #{e.message} tracker=#{tracker.id}")
        nil
      rescue StandardError => e
        Rails.logger.error("[Ledger::EntryPoster] #{e.class} - #{e.message} tracker=#{tracker.id}")
        nil
      end

      def paper_posting?(tracker)
        return true if tracker.paper?

        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      rescue StandardError
        false
      end
    end
  end
end

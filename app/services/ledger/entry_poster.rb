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
          lines: entry_lines(tracker: tracker, gross: gross, fee: fee)
        )
      rescue PostingService::InsufficientCashError => e
        Rails.logger.warn("[Ledger::EntryPoster] #{e.message} tracker=#{tracker.id}")
        nil
      rescue StandardError => e
        Rails.logger.error("[Ledger::EntryPoster] #{e.class} - #{e.message} tracker=#{tracker.id}")
        nil
      end

      # Long: pay cash for the option (an asset you hold, "premium_deployed").
      # Short: receive cash for writing the option (a liability, "premium_written"),
      # and separately lock margin as collateral out of free cash ("margin_blocked").
      def entry_lines(tracker:, gross:, fee:)
        base = [
          { account_code: 'brokerage_expense', debit: fee },
          { account_code: 'cash', credit: fee }
        ]

        if tracker.short_position?
          margin = BigDecimal(tracker.margin_required.to_s)
          base + [
            { account_code: 'cash', debit: gross },
            { account_code: 'premium_written', credit: gross },
            { account_code: 'margin_blocked', debit: margin },
            { account_code: 'cash', credit: margin }
          ]
        else
          base + [
            { account_code: 'premium_deployed', debit: gross },
            { account_code: 'cash', credit: gross }
          ]
        end
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

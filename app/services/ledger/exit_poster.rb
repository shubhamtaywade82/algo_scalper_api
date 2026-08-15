# frozen_string_literal: true

module Ledger
  class ExitPoster
    class << self
      def post!(tracker:, exit_price: nil)
        return nil unless paper_posting?(tracker)
        return nil unless Config.posting_enabled_for_paper?
        return nil unless LedgerJournalEntry.exists?(idempotency_key: "entry:#{tracker.id}")

        Seeder.ensure_ready!

        qty = tracker.quantity.to_i
        return nil unless qty.positive?

        entry_px = BigDecimal((tracker.avg_price || tracker.entry_price).to_s)
        exit_px = BigDecimal((exit_price || tracker.exit_price).to_s)
        exit_fee = BrokerFeeCalculator.fee_per_order

        lines, entry_cost, gross_proceeds, gain =
          if tracker.short_position?
            short_exit_lines(tracker: tracker, qty: qty, entry_px: entry_px, exit_px: exit_px, exit_fee: exit_fee)
          else
            long_exit_lines(qty: qty, entry_px: entry_px, exit_px: exit_px, exit_fee: exit_fee)
          end

        if gain.positive?
          lines << { account_code: 'realized_pnl', credit: gain }
        elsif gain.negative?
          lines << { account_code: 'realized_pnl', debit: gain.abs }
        end

        PostingService.post!(
          idempotency_key: "exit:#{tracker.id}",
          event_type: 'exit_fill',
          mode: :paper,
          position_tracker_id: tracker.id,
          order_no: tracker.exit_order_id || tracker.order_no,
          trading_date: Time.zone.today,
          meta: {
            symbol: tracker.symbol,
            security_id: tracker.security_id,
            gross_proceeds: gross_proceeds.to_f,
            entry_cost: entry_cost.to_f,
            exit_fee: exit_fee.to_f,
            gain: gain.to_f
          },
          lines: lines
        )
      rescue StandardError => e
        Rails.logger.error("[Ledger::ExitPoster] #{e.class} - #{e.message} tracker=#{tracker.id}")
        nil
      end

      def long_exit_lines(qty:, entry_px:, exit_px:, exit_fee:)
        gross_proceeds = (qty * exit_px).round(2)
        entry_cost = (qty * entry_px).round(2)
        gain = gross_proceeds - entry_cost

        lines = [
          { account_code: 'cash', debit: gross_proceeds },
          { account_code: 'premium_deployed', credit: entry_cost },
          { account_code: 'brokerage_expense', debit: exit_fee },
          { account_code: 'cash', credit: exit_fee }
        ]

        [lines, entry_cost, gross_proceeds, gain]
      end

      # Short: buy-to-cover. entry_cost here is the ORIGINAL premium received (booked at
      # entry), buyback_cost is what it costs now to close — the mirror of long_exit_lines
      # with premium_written taking premium_deployed's role, plus releasing the margin
      # that was locked at entry.
      def short_exit_lines(tracker:, qty:, entry_px:, exit_px:, exit_fee:)
        premium_received = (qty * entry_px).round(2)
        buyback_cost = (qty * exit_px).round(2)
        gain = premium_received - buyback_cost
        margin = BigDecimal(tracker.margin_required.to_s)

        lines = [
          { account_code: 'premium_written', debit: premium_received },
          { account_code: 'cash', credit: buyback_cost },
          { account_code: 'margin_blocked', credit: margin },
          { account_code: 'cash', debit: margin },
          { account_code: 'brokerage_expense', debit: exit_fee },
          { account_code: 'cash', credit: exit_fee }
        ]

        [lines, premium_received, buyback_cost, gain]
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

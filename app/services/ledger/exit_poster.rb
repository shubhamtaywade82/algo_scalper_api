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
        gross_proceeds = (qty * exit_px).round(2)
        entry_cost = (qty * entry_px).round(2)
        exit_fee = BrokerFeeCalculator.fee_per_order
        gain = gross_proceeds - entry_cost

        lines = [
          { account_code: 'cash', debit: gross_proceeds },
          { account_code: 'premium_deployed', credit: entry_cost },
          { account_code: 'brokerage_expense', debit: exit_fee },
          { account_code: 'cash', credit: exit_fee }
        ]

        if gain >= 0
          lines << { account_code: 'realized_pnl', credit: gain }
        else
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

      # rubocop:disable Rails/Delegate -- `delegate` targets an instance method, not this class method
      def paper_posting?(tracker)
        EntryPoster.paper_posting?(tracker)
      end
      # rubocop:enable Rails/Delegate
    end
  end
end

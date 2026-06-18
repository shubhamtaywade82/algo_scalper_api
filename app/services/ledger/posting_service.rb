# frozen_string_literal: true

module Ledger
  class PostingService
    class UnbalancedEntryError < StandardError; end
    class InsufficientCashError < StandardError; end

    class << self
      def post!(idempotency_key:, event_type:, mode:, lines:, trading_date: Time.zone.today,
                position_tracker_id: nil, order_no: nil, meta: {})
        existing = LedgerJournalEntry.find_by(idempotency_key: idempotency_key)
        return existing if existing

        normalized = normalize_lines(lines)
        validate_balance!(normalized)
        validate_cash!(normalized) if Config.block_negative_cash?

        LedgerJournalEntry.transaction do
          journal = LedgerJournalEntry.create!(
            idempotency_key: idempotency_key,
            event_type: event_type,
            mode: mode.to_s,
            position_tracker_id: position_tracker_id,
            order_no: order_no,
            trading_date: trading_date,
            meta: meta
          )

          normalized.each do |line|
            account = LedgerAccount.fetch!(line[:account_code])
            debit = line[:debit].to_d
            credit = line[:credit].to_d
            journal.ledger_postings.create!(
              ledger_account: account,
              debit: debit,
              credit: credit
            )
            account.apply_posting!(debit: debit, credit: credit)
          end

          journal
        end
      rescue ActiveRecord::RecordNotUnique
        LedgerJournalEntry.find_by!(idempotency_key: idempotency_key)
      end

      private

      def normalize_lines(lines)
        lines.map do |line|
          debit = line[:debit] || 0
          credit = line[:credit] || 0
          {
            account_code: line[:account_code].to_s,
            debit: BigDecimal(debit.to_s),
            credit: BigDecimal(credit.to_s)
          }
        end
      end

      def validate_balance!(lines)
        debits = lines.sum { |line| line[:debit] }
        credits = lines.sum { |line| line[:credit] }
        return if debits == credits

        raise UnbalancedEntryError, "debits=#{debits} credits=#{credits}"
      end

      def validate_cash!(lines)
        cash = LedgerAccount.fetch!('cash')
        cash_delta = lines.select { |line| line[:account_code] == 'cash' }
                          .sum { |line| line[:debit] - line[:credit] }
        projected = cash.balance_cache.to_d + cash_delta
        return if projected >= 0

        raise InsufficientCashError, "cash would be #{projected}"
      end
    end
  end
end

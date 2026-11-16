# frozen_string_literal: true

module Api
  module LedgerEntrySerialization
    extend ActiveSupport::Concern

    private

    def serialize_entry(entry)
      {
        id: entry.id,
        idempotency_key: entry.idempotency_key,
        event_type: entry.event_type,
        mode: entry.mode,
        position_tracker_id: entry.position_tracker_id,
        order_no: entry.order_no,
        trading_date: entry.trading_date,
        meta: entry.meta,
        created_at: entry.created_at.iso8601,
        postings: entry.ledger_postings.map do |posting|
          {
            account_code: posting.ledger_account.code,
            account_name: posting.ledger_account.name,
            debit: posting.debit.to_f,
            credit: posting.credit.to_f
          }
        end
      }
    end
  end
end

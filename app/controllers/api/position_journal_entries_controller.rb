# frozen_string_literal: true

module Api
  # GET /api/positions/:position_id/journal_entries — every ledger entry for one position.
  class PositionJournalEntriesController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::LedgerEntrySerialization

    before_action :authenticate_dashboard_token!

    def index
      tracker = PositionTracker.find(params.expect(:position_id))
      entries = LedgerJournalEntry.where(position_tracker_id: tracker.id).includes(ledger_postings: :ledger_account)

      render json: {
        success: true,
        position_tracker_id: tracker.id,
        entries: entries.map { |entry| serialize_entry(entry) }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'position_not_found' }, status: :not_found
    end
  end
end

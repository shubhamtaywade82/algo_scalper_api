# frozen_string_literal: true

module Api
  # GET /api/ledger/journal — paginated journal, filterable by event_type / position_tracker_id.
  class LedgerJournalEntriesController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::LedgerEntrySerialization

    before_action :authenticate_dashboard_token!

    def index
      scope = LedgerJournalEntry.recent.includes(ledger_postings: :ledger_account)
      scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
      scope = scope.where(position_tracker_id: params[:position_tracker_id]) if params[:position_tracker_id].present?

      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 25].max, 100].min
      total = scope.count
      entries = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        success: true,
        entries: entries.map { |entry| serialize_entry(entry) },
        meta: {
          total: total,
          page: page,
          per_page: per_page,
          pages: (total.to_f / per_page).ceil
        }
      }
    end
  end
end

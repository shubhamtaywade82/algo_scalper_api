# frozen_string_literal: true

module Api
  class LedgerController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def balance
      Ledger::Seeder.ensure_ready!
      snapshot = Ledger::WalletReader.snapshot(mode: :paper)
      accounts = LedgerAccount.order(:code).map do |account|
        {
          code: account.code,
          name: account.name,
          account_type: account.account_type,
          balance: account.balance_cache.to_f
        }
      end

      render json: {
        success: true,
        wallet: snapshot,
        accounts: accounts,
        reconciliation: Ledger::BalanceChecker.compare_paper_wallet,
        config: {
          enabled: Ledger::Config.enabled?,
          paper_enabled: Ledger::Config.paper_enabled?,
          shadow_mode: Ledger::Config.shadow_mode?
        }
      }
    end

    def journal
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

    def position
      tracker = PositionTracker.find(params[:id])
      entries = LedgerJournalEntry.where(position_tracker_id: tracker.id).includes(ledger_postings: :ledger_account)

      render json: {
        success: true,
        position_tracker_id: tracker.id,
        entries: entries.map { |entry| serialize_entry(entry) }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'position_not_found' }, status: :not_found
    end

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

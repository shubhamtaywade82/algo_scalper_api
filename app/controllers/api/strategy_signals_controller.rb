# frozen_string_literal: true

module Api
  # Signals emitted by a strategy, paginated.
  class StrategySignalsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!
    before_action :find_strategy

    # GET /api/strategies/:strategy_slug/signals
    def index
      scope = @strategy.signals.order(emitted_at: :desc)
      scope = scope.where(action: params[:filter_action]) if params[:filter_action].present?
      scope = scope.where(outcome: params[:outcome]) if params[:outcome].present?

      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 1].max, 200].min
      total = scope.count
      records = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        success: true,
        signals: records.map { |s| serialize_signal(s) },
        meta: { total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil }
      }
    end

    private

    def serialize_signal(s)
      {
        id: s.id,
        instrument_key: s.instrument_key,
        action: s.action,
        confidence: s.confidence,
        reason: s.reason,
        outcome: s.outcome,
        emitted_at: s.emitted_at
      }
    end
  end
end

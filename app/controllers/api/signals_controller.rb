# frozen_string_literal: true

module Api
  class SignalsController < ApplicationController
    PER_PAGE_DEFAULT = 25
    PER_PAGE_MAX     = 100
    ALLOWED_SORT_COLS = %w[signal_timestamp confidence_score adx_value index_key direction created_at].freeze

    def index
      scope = TradingSignal.order(signal_timestamp: :desc).limit(100)
      scope = apply_filters(scope)
      total = scope.count
      scope = apply_sort(scope)
      scope = apply_pagination(scope)

      render json: {
        signals: scope.map { |sig| serialize(sig) },
        meta: {
          total:    total,
          page:     current_page,
          per_page: per_page_value,
          pages:    (total.to_f / per_page_value).ceil
        }
      }
    end

    private

    def apply_filters(scope)
      scope = scope.for_index(params[:index_key].upcase) if params[:index_key].present?
      scope = scope.for_direction(params[:direction])    if params[:direction].present?

      if params[:outcome].present?
        scope = scope.where("metadata->>'entry_outcome' = ?", params[:outcome])
      end

      if params[:confidence_min].present?
        min = params[:confidence_min].to_f.clamp(0.0, 1.0)
        scope = scope.where("confidence_score >= ?", min)
      end

      if params[:date_from].present?
        d = parse_date(params[:date_from])
        scope = scope.where("signal_timestamp >= ?", d.beginning_of_day) if d
      end

      if params[:date_to].present?
        d = parse_date(params[:date_to])
        scope = scope.where("signal_timestamp <= ?", d.end_of_day) if d
      end

      scope
    end

    def apply_sort(scope)
      col = ALLOWED_SORT_COLS.include?(params[:sort_by]) ? params[:sort_by] : "signal_timestamp"
      dir = params[:sort_dir] == "asc" ? :asc : :desc
      scope.order(col => dir)
    end

    def apply_pagination(scope)
      scope.offset((current_page - 1) * per_page_value).limit(per_page_value)
    end

    def current_page
      [params[:page].to_i, 1].max
    end

    def per_page_value
      raw = params[:per_page].to_i
      raw = PER_PAGE_DEFAULT if raw <= 0
      [raw, PER_PAGE_MAX].min
    end

    def serialize(sig)
      {
        id:                sig.id,
        index_key:         sig.index_key,
        direction:         sig.direction,
        confidence_score:  sig.confidence_score&.to_f,
        confidence_level:  sig.confidence_level,
        timeframe:         sig.timeframe,
        supertrend_value:  sig.supertrend_value&.to_f,
        adx_value:         sig.adx_value&.to_f,
        signal_timestamp:  sig.signal_timestamp&.iso8601,
        candle_timestamp:  sig.candle_timestamp&.iso8601,
        metadata:          sig.metadata || {}
      }
    end

    def parse_date(str)
      Date.parse(str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

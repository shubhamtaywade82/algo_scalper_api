# frozen_string_literal: true

module Api
  class SignalsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    PER_PAGE_DEFAULT = 25
    PER_PAGE_MAX     = 100
    ALLOWED_SORT_COLS = %w[emitted_at confidence].freeze
    DIRECTION_BY_ACTION = { "buy_call" => "bullish", "buy_put" => "bearish" }.freeze
    ENTRY_OUTCOME_BY_OUTCOME = {
      "executed" => "entered",
      "blocked_by_guard" => "blocked",
      "ignored_hold" => "skipped",
      "shadow" => "skipped"
    }.freeze
    ADX_IN_REASON = /adx_([\d.]+)/

    # Live signals now come from the Strategies::Manager plugin platform
    # (strategy_signals table) — the legacy Signal::Engine → TradingSignal
    # pipeline was removed in b3a8f30 and no longer writes new rows.
    def index
      scope = TradingSignal.order(signal_timestamp: :desc).limit(100)
      scope = apply_filters(scope)
      total = scope.count
      scope = apply_sort(scope)
      scope = apply_pagination(scope)

      render json: {
        signals: scope.map { |sig| serialize(sig) },
        meta: {
          total: total,
          page: current_page,
          per_page: per_page_value,
          pages: (total.to_f / per_page_value).ceil
        }
      }
    end

    private

    def apply_filters(scope)
      scope = scope.where(instrument_key: params[:index_key].upcase) if params[:index_key].present?

      if params[:direction].present?
        actions = DIRECTION_BY_ACTION.select { |_, dir| dir == params[:direction] }.keys
        scope = scope.where(action: actions)
      end

      if params[:outcome].present?
        outcomes = ENTRY_OUTCOME_BY_OUTCOME.select { |_, o| o == params[:outcome] }.keys
        scope = scope.where(outcome: outcomes)
      end

      if params[:confidence_min].present?
        min = params[:confidence_min].to_f.clamp(0.0, 1.0)
        scope = scope.where(confidence: min..)
      end

      if params[:date_from].present?
        d = parse_date(params[:date_from])
        scope = scope.where(emitted_at: d.beginning_of_day..) if d
      end

      if params[:date_to].present?
        d = parse_date(params[:date_to])
        scope = scope.where(emitted_at: ..d.end_of_day) if d
      end

      scope
    end

    def apply_sort(scope)
      col = ALLOWED_SORT_COLS.include?(params[:sort_by]) ? params[:sort_by] : "emitted_at"
      dir = params[:sort_dir] == "asc" ? :asc : :desc
      scope.reorder(col => dir)
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
      confidence = sig.confidence&.to_f
      adx_match = sig.reason.to_s.match(ADX_IN_REASON)

      {
        id: sig.id,
        index_key: sig.instrument_key,
        direction: DIRECTION_BY_ACTION[sig.action] || "none",
        confidence_score: confidence,
        confidence_level: confidence_level_for(confidence),
        timeframe: sig.strategy_version&.manifest&.dig("timeframes", 0),
        supertrend_value: nil,
        adx_value: adx_match && adx_match[1].to_f,
        signal_timestamp: sig.emitted_at&.iso8601,
        candle_timestamp: sig.emitted_at&.iso8601,
        metadata: {
          strategy: sig.strategy_record&.slug,
          entry_outcome: ENTRY_OUTCOME_BY_OUTCOME[sig.outcome] || "skipped",
          reason: sig.reason,
          entry_blocked_reason: sig.outcome == "blocked_by_guard" ? sig.metadata["entry_result_reason"] : nil,
          entry_blocked_guard_results: sig.outcome == "blocked_by_guard" ? sig.metadata["guard_results"] : nil,
          entry_skip_stage: sig.outcome == "blocked_by_guard" ? nil : "strategy_platform",
          entry_skip_code: sig.outcome == "blocked_by_guard" ? nil : sig.reason
        }
      }
    end

    def confidence_level_for(score)
      return "unknown" unless score

      case score
      when 0.8..1.0 then "very_high"
      when 0.6...0.8 then "high"
      when 0.4...0.6 then "medium"
      when 0.2...0.4 then "low"
      else "very_low"
      end
    end

    def parse_date(str)
      Date.parse(str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

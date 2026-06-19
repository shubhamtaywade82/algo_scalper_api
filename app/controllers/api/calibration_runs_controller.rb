# frozen_string_literal: true

module Api
  class CalibrationRunsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[index show]
    before_action :authenticate_settings!, only: :apply

    SNAPSHOT_PATHS = [
      %w[risk percentage_pnl_exit target_pct],
      %w[risk trailing activation_pct],
      %w[risk trailing drawdown_pct],
      %w[risk profit_floor lock_pct],
      %w[risk profit_floor trail_pct]
    ].freeze

    def index
      limit = [[params.fetch(:limit, 20).to_i, 1].max, 100].min
      scope = CalibrationRun.order(created_at: :desc)
      scope = scope.where(symbol: params[:symbol].to_s.upcase) if params[:symbol].present?

      runs = scope.limit(limit)
      snapshot = current_snapshot

      render json: {
        success: true,
        runs: runs.map { |run| serialize_run(run, snapshot) },
        current_snapshot: snapshot
      }
    end

    def show
      run = CalibrationRun.find(params[:id])
      snapshot = current_snapshot
      render json: { success: true, run: serialize_run(run, snapshot), current_snapshot: snapshot }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'not found' }, status: :not_found
    end

    def apply
      run = CalibrationRun.find(params[:id])
      run.apply!(applied_by: 'api')
      render json: { success: true, run: serialize_run(run.reload, current_snapshot) }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'not found' }, status: :not_found
    rescue RuntimeError => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] apply error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def serialize_run(run, snapshot)
      {
        id: run.id,
        symbol: run.symbol,
        weeks_analyzed: run.weeks_analyzed,
        strike_mode: run.strike_mode,
        raw_stats: run.raw_stats,
        proposed_patch: run.proposed_patch,
        is_regime_shift: run.is_regime_shift,
        regime_reason: run.regime_reason,
        applied_at: run.applied_at,
        applied_by: run.applied_by,
        created_at: run.created_at,
        pending: run.applied_at.nil?
      }
    end

    def current_snapshot
      config = AlgoConfig.fetch
      trailing = config.dig(:risk, :institutional_trailing) || {}

      base = SNAPSHOT_PATHS.to_h { |path| [path.join('.'), config.dig(*path.map(&:to_sym))] }

      trailing.each do |index_key, params|
        next unless params.is_a?(Hash)

        params.each do |param_key, value|
          base["risk.institutional_trailing.#{index_key}.#{param_key}"] = value
        end
      end

      base
    end
  end
end

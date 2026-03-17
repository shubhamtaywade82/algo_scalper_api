# frozen_string_literal: true

module Api
  class CalibrationRunsController < ApplicationController
    # GET /api/calibration_runs
    # Returns last N runs ordered by created_at desc, with current_snapshot.
    def index
      limit = (params[:limit] || 10).to_i.clamp(1, 50)
      runs  = CalibrationRun.order(created_at: :desc).limit(limit).to_a
      snap  = current_config_snapshot

      render json: runs.map { |r| r.as_json.merge('current_snapshot' => snap) }
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] index error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # GET /api/calibration_runs/:id
    def show
      run = CalibrationRun.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless run

      render json: run.as_json.merge('current_snapshot' => current_config_snapshot)
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] show error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # POST /api/calibration_runs/:id/apply
    def apply
      run = CalibrationRun.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless run

      run.apply!(applied_by: 'api')
      render json: run.as_json
    rescue RuntimeError => e
      # apply! raises RuntimeError('already applied') for double-apply
      render json: { error: e.message }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] apply error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    private

    # Single AlgoConfig.fetch per request; extracts all keys that
    # CalibrationConfigPatchBuilder may emit so frontend can compute diff.
    def current_config_snapshot
      cfg = AlgoConfig.fetch
      {
        'risk.percentage_pnl_exit.target_pct' => cfg.dig(:risk, :percentage_pnl_exit, :target_pct),
        'risk.trailing.activation_pct' => cfg.dig(:risk, :trailing, :activation_pct),
        'risk.trailing.drawdown_pct' => cfg.dig(:risk, :trailing, :drawdown_pct),
        'risk.profit_floor.lock_pct' => cfg.dig(:risk, :profit_floor, :lock_pct),
        'risk.profit_floor.trail_pct' => cfg.dig(:risk, :profit_floor, :trail_pct),
        'institutional_trailing.trailing_distance' => cfg.dig(:risk, :institutional_trailing, :trailing_distance),
        'institutional_trailing.early_trigger' => cfg.dig(:risk, :institutional_trailing, :early_trigger),
        'institutional_trailing.breakeven_trigger' => cfg.dig(:risk, :institutional_trailing, :breakeven_trigger),
        'institutional_trailing.activation_trigger' => cfg.dig(:risk, :institutional_trailing, :activation_trigger)
      }
    rescue StandardError
      {}
    end
  end
end

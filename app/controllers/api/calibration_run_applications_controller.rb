# frozen_string_literal: true

module Api
  # POST /api/calibration_runs/:calibration_run_id/application — applies the run's config patch.
  class CalibrationRunApplicationsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_operator_token!

    def create
      run = CalibrationRun.find_by(id: params[:calibration_run_id])
      return render json: { error: 'not found' }, status: :not_found unless run

      run.apply!(applied_by: 'api')
      render json: run.as_json
    rescue RuntimeError => e
      # apply! raises RuntimeError('already applied') for double-apply
      render json: { error: e.message }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunApplicationsController] apply error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end
  end
end

# frozen_string_literal: true

module Api
  class ScheduledTaskExecutionsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::RecurringSchedule

    before_action :authenticate_dashboard_token!

    # Static allowlist of permissible recurring jobs to eliminate reflection risks
    ALLOWED_TASK_JOBS = {
      "InstrumentsImportJob" => InstrumentsImportJob,
      "PortfolioResetJob" => PortfolioResetJob,
      "ClearCarriedOvernightPositionsJob" => ClearCarriedOvernightPositionsJob,
      "SmcScannerJob" => SmcScannerJob,
      "Ai::AgentsCycleJob" => Ai::AgentsCycleJob,
      "AnalysisJob" => AnalysisJob,
      "Reports::MarketBriefJob" => Reports::MarketBriefJob,
      "AiTechnicalAnalysisJob" => AiTechnicalAnalysisJob,
      "Dhan::AutoIpUpdaterJob" => Dhan::AutoIpUpdaterJob,
      "PublicIpLogJob" => PublicIpLogJob,
      "Live::CancelStuckOrdersJob" => Live::CancelStuckOrdersJob,
      "Ledger::DailyCloseJob" => Ledger::DailyCloseJob,
      "DataQuality::TickStalenessSamplerJob" => DataQuality::TickStalenessSamplerJob,
      "DataQuality::DailyCheckJob" => DataQuality::DailyCheckJob,
      "WeeklyCalibrationJob" => WeeklyCalibrationJob
    }.freeze

    # POST /api/scheduler/tasks/:task_id/executions — enqueue the task now
    def create
      task_id = params[:task_id]
      schedule_config = load_schedule_config
      config = schedule_config[task_id]

      if config.nil?
        render json: { success: false, error: "task_not_found" }, status: :not_found
        return
      end

      job_class_name = config["class"]
      klass = ALLOWED_TASK_JOBS[job_class_name]
      if klass.nil?
        render json: { success: false, error: "invalid_job_class" }, status: :unprocessable_content
        return
      end

      begin
        args = Array(config["args"])

        if args.present?
          klass.perform_later(*args)
        else
          klass.perform_later
        end

        render json: { success: true, message: "Job #{job_class_name} enqueued successfully" }
      rescue StandardError => e
        Rails.logger.error("[Api::ScheduledTaskExecutionsController] Failed to enqueue job #{job_class_name}: #{e.message}")
        render json: { success: false, error: "enqueue_failed", message: e.message }, status: :internal_server_error
      end
    end
  end
end

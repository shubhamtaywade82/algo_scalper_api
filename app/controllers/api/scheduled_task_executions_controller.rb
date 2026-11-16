# frozen_string_literal: true

module Api
  class ScheduledTaskExecutionsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::RecurringSchedule

    before_action :authenticate_dashboard_token!

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
      if job_class_name.blank?
        render json: { success: false, error: "invalid_job_class" }, status: :unprocessable_content
        return
      end

      # Only valid Ruby constant paths may be resolved (defense in depth: the
      # value comes from the repo-owned recurring.yml, but a malformed entry
      # should 422 cleanly instead of reaching constantize).
      unless job_class_name.match?(/\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/)
        render json: { success: false, error: "invalid_job_class" }, status: :unprocessable_content
        return
      end

      begin
        klass = job_class_name.constantize
        args = Array(config["args"])

        if args.present?
          klass.perform_later(*args)
        else
          klass.perform_later
        end

        render json: { success: true, message: "Job #{job_class_name} enqueued successfully" }
      rescue NameError => e
        Rails.logger.error("[Api::ScheduledTaskExecutionsController] Job class #{job_class_name} name error: #{e.message}")
        render json: { success: false, error: "job_class_not_defined", message: e.message }, status: :internal_server_error
      rescue StandardError => e
        Rails.logger.error("[Api::ScheduledTaskExecutionsController] Failed to enqueue job #{job_class_name}: #{e.message}")
        render json: { success: false, error: "enqueue_failed", message: e.message }, status: :internal_server_error
      end
    end
  end
end

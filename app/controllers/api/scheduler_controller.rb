# frozen_string_literal: true

module Api
  class SchedulerController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      schedule_config = load_schedule_config
      last_runs = latest_recurring_runs(schedule_config.keys)
      tasks = schedule_config.map do |key, config|
        run = last_runs[key]
        {
          id: key,
          name: key.to_s.titleize,
          schedule: config["schedule"],
          cron: config["schedule"],
          status: run ? run_status(run.job) : "pending",
          last_run_at: run&.run_at&.iso8601,
          next_run_at: SolidQueue::RecurringTask.find_by(key: key)&.next_time&.in_time_zone&.iso8601,
          description: config["description"] || "Scheduled background system job"
        }
      end

      render json: tasks
    end

    def execute
      task_id = params[:id]
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
        Rails.logger.error("[Api::SchedulerController] Job class #{job_class_name} name error: #{e.message}")
        render json: { success: false, error: "job_class_not_defined", message: e.message }, status: :internal_server_error
      rescue StandardError => e
        Rails.logger.error("[Api::SchedulerController] Failed to enqueue job #{job_class_name}: #{e.message}")
        render json: { success: false, error: "enqueue_failed", message: e.message }, status: :internal_server_error
      end
    end

    private

    def latest_recurring_runs(keys)
      SolidQueue::RecurringExecution.where(task_key: keys).includes(job: :failed_execution)
                                    .order(:run_at).index_by(&:task_key)
    end

    def run_status(job)
      return "unknown" unless job
      return "failed" if job.failed_execution
      return "completed" if job.finished_at

      "running"
    end

    def load_schedule_config
      path = Rails.root.join("config/recurring.yml")
      return {} unless File.exist?(path)

      begin
        all_config = YAML.load_file(path)
        all_config[Rails.env] || {}
      rescue StandardError => e
        Rails.logger.error("[Api::SchedulerController] Failed to load recurring.yml: #{e.message}")
        {}
      end
    end
  end
end

# frozen_string_literal: true

module Api
  # GET /api/scheduler/tasks — recurring.yml tasks with their last/next run.
  class ScheduledTasksController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::RecurringSchedule

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

    private

    def latest_recurring_runs(keys)
      # Table grows unbounded (one row per run); fetch only the newest row per key.
      newest_ids = SolidQueue::RecurringExecution.where(task_key: keys).group(:task_key).maximum(:id).values
      SolidQueue::RecurringExecution.where(id: newest_ids).includes(job: :failed_execution).index_by(&:task_key)
    end

    def run_status(job)
      return "unknown" unless job
      return "failed" if job.failed_execution
      return "completed" if job.finished_at

      "running"
    end
  end
end

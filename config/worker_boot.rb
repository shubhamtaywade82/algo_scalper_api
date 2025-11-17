# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "production"

require_relative "../config/environment"

Rails.logger.info("[WorkerBoot] Starting trading supervisor in worker container... pid=#{Process.pid}")

# Supervisor auto-starts only when:
#   DISABLE_TRADING_SUPERVISOR != "true"
#   WORKER_MODE = "true" (optional)
Rails.application.config.x.trading_supervisor

Rails.logger.info("[WorkerBoot] TradingSystem supervisor is running...")

# Keep process alive forever
sleep

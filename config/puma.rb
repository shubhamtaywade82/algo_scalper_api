# frozen_string_literal: true

# ---------------------------------------------------------
# Puma configuration for algo_scalper_api
# ---------------------------------------------------------
# Why:
# - ExitEngine + RiskManagerService + FeedHub run in threads
# - Workers are disabled because forking breaks thread supervisors
# - Ideal for Docker & Render/Heroku/Kamal deployments
# ---------------------------------------------------------

# Thread pool size: Rails + FeedHub + ExitEngine need headroom
max_threads = Integer(ENV.fetch("RAILS_MAX_THREADS", 8))
min_threads = Integer(ENV.fetch("RAILS_MIN_THREADS", max_threads))
threads min_threads, max_threads

# Environment setup
environment ENV.fetch("RAILS_ENV", "development")

# Bind to PORT=3000 inside Docker
port ENV.fetch("PORT", 3000)

# Allow `rails restart`
plugin :tmp_restart

# ---------------------------------------------------------
# ** DO NOT ENABLE WORKERS **
# (Multi-process forking breaks background thread systems)
# ---------------------------------------------------------
# workers ENV.fetch("WEB_CONCURRENCY", 1)
# preload_app!

# ---------------------------------------------------------
# PID & state files (production only)
# ---------------------------------------------------------
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# ---------------------------------------------------------
# Graceful shutdown: stop ExitEngine + FeedHub threads
# ---------------------------------------------------------
before_fork do
  # nothing here because we do NOT fork workers (by design)
end

on_worker_shutdown do
  # not applicable: single-process mode
end

# ---------------------------------------------------------
# Rails hooks for shutting down long-running threads
# ---------------------------------------------------------
on_restart do
  Rails.logger.info("[Puma] Restarting, stopping background services...")
  # Best-effort teardown — but never silent: a swallowed stop failure would
  # leave duplicate engine threads running after the restart.
  begin
    Rails.logger.info("[Puma] Stopping Live::ExitEngine") if defined?(Live::ExitEngine)
    Live::ExitEngine.instance.stop if defined?(Live::ExitEngine)
  rescue StandardError => e
    Rails.logger.error("[Puma] Failed to stop Live::ExitEngine: #{e.class} - #{e.message}")
  end
  begin
    Rails.logger.info("[Puma] Stopping Live::MarketFeedHub") if defined?(Live::MarketFeedHub)
    Live::MarketFeedHub.instance.stop! if defined?(Live::MarketFeedHub)
  rescue StandardError => e
    Rails.logger.error("[Puma] Failed to stop Live::MarketFeedHub: #{e.class} - #{e.message}")
  end
end

# ---------------------------------------------------------
# Additional optimizations
# ---------------------------------------------------------
# Reduce boot noise
quiet

# Log to STDOUT in Docker
stdout_redirect(
  ENV.fetch("PUMA_STDOUT", "log/puma.stdout.log"),
  ENV.fetch("PUMA_STDERR", "log/puma.stderr.log"),
  true
) unless ENV["RAILS_LOG_TO_STDOUT"] == "true"

# frozen_string_literal: true

# Sync paper positions from PositionTracker (PostgreSQL) to Redis on startup
# This ensures positions survive server restarts even if Redis is cleared
Rails.application.config.to_prepare do
  next unless ExecutionMode.paper?
  next if Rails.const_defined?(:Console) || Rails.env.test?

  # Run sync after Orders.config is initialized
  Rails.application.config.after_initialize do
    begin
      result = Paper::PositionSync.sync!
      Rails.logger.info("[PaperSync] Position sync completed: #{result.inspect}")
    rescue StandardError => e
      Rails.logger.error("[PaperSync] Position sync failed: #{e.class} - #{e.message}")
      Rails.logger.error("[PaperSync] Backtrace: #{e.backtrace.first(5).join(', ')}")
    end
  end
end



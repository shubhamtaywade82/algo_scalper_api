# frozen_string_literal: true

# Job to execute AI technical analysis rake task
require 'English'
class AiTechnicalAnalysisJob < ApplicationJob
  queue_as :background

  def perform(index_name)
    market_closed = TradingSession::Service.market_closed?

    if market_closed
      # Market is closed - analyze for next trading day
      next_trading_date = Market::Calendar.next_trading_day
      query = "OPTIONS buying intraday for next trading day (#{next_trading_date.strftime('%Y-%m-%d')}) in INDEX like #{index_name}"
      Rails.logger.info("[AiTechnicalAnalysisJob] Market closed - analyzing #{index_name} for next trading day (#{next_trading_date.strftime('%Y-%m-%d')})")
    else
      # Market is open - analyze for current trading session
      query = "OPTIONS buying intraday in INDEX like #{index_name}"
      Rails.logger.info("[AiTechnicalAnalysisJob] Running analysis for #{index_name} (current trading session)")
    end

    # Execute the rake task with STREAM environment variable
    # Change to Rails root directory and execute
    Dir.chdir(Rails.root) do
      # Set environment variable and execute command
      result = system({ 'STREAM' => 'true' }, "bundle exec rake 'ai:technical_analysis[\"#{query}\"]'")

      if result
        Rails.logger.info("[AiTechnicalAnalysisJob] Successfully executed for #{index_name}")
      else
        Rails.logger.error("[AiTechnicalAnalysisJob] Failed to execute for #{index_name} (exit code: #{$CHILD_STATUS.exitstatus})")
      end
    end
  rescue StandardError => e
    Rails.logger.error("[AiTechnicalAnalysisJob] Error: #{e.class} - #{e.message}")
    Rails.logger.error("[AiTechnicalAnalysisJob] Backtrace: #{e.backtrace.first(5).join("\n")}")
    raise
  end
end

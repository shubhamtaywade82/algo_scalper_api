# frozen_string_literal: true

# Job to execute AI technical analysis rake task
require 'English'
class AiTechnicalAnalysisJob < ApplicationJob
  queue_as :background

  @chdir_mutex = Mutex.new

  class << self
    attr_reader :chdir_mutex
  end

  def perform(index_name)
    market_closed = TradingSession::Service.market_closed?

    if market_closed
      next_trading_date = Market::Calendar.next_trading_day
      target_date = next_trading_date.strftime('%Y-%m-%d')
      session = closed_market_session_label
      reason = 'overnight_research'
      query = "OPTIONS buying intraday for next trading day (#{target_date}) in INDEX like #{index_name}"

      cache_key = "ai_tech_analysis:logged_closed:#{Time.zone.today}:#{index_name}"
      first_log_for_today = Rails.cache.read(cache_key).nil?
      Rails.cache.write(cache_key, true, expires_in: 1.day) if first_log_for_today

      if first_log_for_today
        Rails.logger.info(
          "[AiTechnicalAnalysisJob] Market closed - analyzing #{index_name} for next trading day " \
          "(reason=#{reason}, session=#{session}, target_date=#{target_date})"
        )
      else
        Rails.logger.debug do
          "[AiTechnicalAnalysisJob] Market closed - analyzing #{index_name} " \
            "(reason=#{reason}, session=#{session}, target_date=#{target_date})"
        end
      end
    else
      query = "OPTIONS buying intraday in INDEX like #{index_name}"
      Rails.logger.info("[AiTechnicalAnalysisJob] Running analysis for #{index_name} (current trading session)")
    end

    # Execute the rake task with STREAM environment variable
    # Change to Rails root directory and execute
    # Use mutex to serialize chdir operations (Dir.chdir is not thread-safe)
    self.class.chdir_mutex.synchronize do
      Dir.chdir(Rails.root) do
        # Set environment variable and execute command
        result = system({ 'STREAM' => 'true' }, "bundle exec rake 'ai:technical_analysis[\"#{query}\"]'")

        if result
          Rails.logger.info("[AiTechnicalAnalysisJob] Successfully executed for #{index_name}")
        else
          Rails.logger.error("[AiTechnicalAnalysisJob] Failed to execute for #{index_name} (exit code: #{$CHILD_STATUS.exitstatus})")
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error("[AiTechnicalAnalysisJob] Error: #{e.class} - #{e.message}")
    Rails.logger.error("[AiTechnicalAnalysisJob] Backtrace: #{e.backtrace.first(5).join("\n")}")
    raise
  end

  private

  def closed_market_session_label
    regime = Live::TimeRegimeService.instance.current_regime
    case regime
    when Live::TimeRegimeService::POST_MARKET then 'POST_MARKET'
    when Live::TimeRegimeService::PRE_MARKET then 'PRE_MARKET'
    else regime.to_s.upcase
    end
  rescue StandardError
    'CLOSED'
  end
end

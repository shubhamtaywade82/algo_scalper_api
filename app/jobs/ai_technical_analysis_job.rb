# frozen_string_literal: true

# Job to execute AI technical analysis rake task
require 'English'
class AiTechnicalAnalysisJob < ApplicationJob
  queue_as :background

  # Mutex to serialize chdir operations (Dir.chdir is not thread-safe)
  @chdir_mutex = Mutex.new

  class << self
    attr_reader :chdir_mutex
  end

  def perform(index_name)
    index_key = validate_index_key!(index_name)

    if AlgoConfig.scheduled_ai_technical_analysis_job_deferred?
      Rails.logger.info(
        "[AiTechnicalAnalysisJob] Skipped #{index_key}: event-driven intraday AI " \
        '(signals.event_driven_ai_alerts or tick_ai_analysis_enabled). Trading daemon tick path ' \
        'owns open-session alerts; SCHEDULED_AI_TECHNICAL_ANALYSIS=true forces this job.'
      )
      return
    end

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
  rescue StandardError => e
    Rails.logger.error("[AiTechnicalAnalysisJob] Error: #{e.class} - #{e.message}")
    Rails.logger.error("[AiTechnicalAnalysisJob] Backtrace: #{e.backtrace.first(5).join("\n")}")
    raise
  end

  private

  def validate_index_key!(name)
    key = name.to_s.upcase.strip
    indices = IndexConfigLoader.load_indices
    allowed = indices.to_set { |i| i[:key].to_s.upcase }
    if allowed.empty?
      raise ArgumentError,
            '[AiTechnicalAnalysisJob] No indices loaded from IndexConfigLoader; refusing to run subprocess'
    end
    return key if allowed.include?(key)

    raise ArgumentError, "[AiTechnicalAnalysisJob] Unknown index_name #{name.inspect} (allowed: #{allowed.to_a.sort.join(', ')})"
  end

  def closed_market_session_label
    Live::TimeRegimeService.closed_session_label
  end
end

# frozen_string_literal: true

# Job to execute AI technical analysis rake task
require 'open3'

class AiTechnicalAnalysisJob < ApplicationJob
  queue_as :background

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
      next_trading_date = Market::Calendar.next_trading_day
      target_date = next_trading_date.strftime('%Y-%m-%d')
      session = closed_market_session_label
      reason = 'overnight_research'
      query = "OPTIONS buying intraday for next trading day (#{target_date}) in INDEX like #{index_key}"

      cache_key = "ai_tech_analysis:logged_closed:#{Time.zone.today}:#{index_key}"
      first_log_for_today = Rails.cache.read(cache_key).nil?
      Rails.cache.write(cache_key, true, expires_in: 1.day) if first_log_for_today

      if first_log_for_today
        Rails.logger.info(
          "[AiTechnicalAnalysisJob] Market closed - analyzing #{index_key} for next trading day " \
          "(reason=#{reason}, session=#{session}, target_date=#{target_date})"
        )
      else
        Rails.logger.debug do
          "[AiTechnicalAnalysisJob] Market closed - analyzing #{index_key} " \
            "(reason=#{reason}, session=#{session}, target_date=#{target_date})"
        end
      end
    else
      query = "OPTIONS buying intraday in INDEX like #{index_key}"
      Rails.logger.info("[AiTechnicalAnalysisJob] Running analysis for #{index_key} (current trading session)")
    end

    # Run rake in a subprocess with argv only (no shell). Pass the prompt via +QUERY+ (see
    # +lib/tasks/ai_technical_analysis.rake+) so the task argument is static. Rake may call +exit+
    # on failure; isolating in a child avoids killing the job worker.
    env = { 'STREAM' => 'true', 'QUERY' => query }
    self.class.chdir_mutex.synchronize do
      output, status = Open3.capture2e(
        env,
        'bundle', 'exec', 'rake', 'ai:technical_analysis',
        chdir: Rails.root.to_s
      )

      if status.success?
        Rails.logger.info("[AiTechnicalAnalysisJob] Successfully executed for #{index_key}")
      else
        Rails.logger.error(
          "[AiTechnicalAnalysisJob] Failed for #{index_key} (exit=#{status.exitstatus}): " \
          "#{output.to_s.truncate(800)}"
        )
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

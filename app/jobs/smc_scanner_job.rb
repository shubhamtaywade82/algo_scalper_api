# frozen_string_literal: true

require_relative '../../lib/telegram_notifier'

# Background job to run SMC scanner for all configured indices
class SmcScannerJob < ApplicationJob
  queue_as :background

  # Retry with exponential backoff for transient failures
  # Use proc for exponential backoff: 2^attempt seconds
  retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 3

  def perform
    if AlgoConfig.scheduled_smc_scanner_job_deferred?
      Rails.logger.info(
        '[SmcScannerJob] Skipped intraday scheduled scan: event-driven AI ' \
        '(event_driven_ai_alerts or tick_ai_analysis_enabled). Use trading daemon + tick path; ' \
        'SCHEDULED_SMC_SCANNER=true forces this job.'
      )
      return
    end

    Rails.logger.info('[SmcScannerJob] Starting SMC scan...')

    if TradingSession::Service.market_closed?
      target_date = Market::Calendar.next_trading_day.strftime('%Y-%m-%d')
      session = closed_market_session_label
      Rails.logger.debug do
        "[SmcScannerJob] Running while market closed (reason=overnight_research, session=#{session}, target_date=#{target_date})"
      end
    end

    indices = IndexConfigLoader.load_indices
    Rails.logger.info("[SmcScannerJob] Loaded #{indices.size} indices from config...")

    # Filter indices by expiry (only analyze indices with expiry <= 7 days)
    filtered_indices = filter_indices_by_expiry(indices)
    Rails.logger.info("[SmcScannerJob] Scanning #{filtered_indices.size} indices (after expiry filter)...")

    success_count = 0
    error_count = 0

    filtered_indices.each_with_index do |idx_cfg, index|
      # Add delay between instruments (except first one)
      if index.positive?
        Rails.logger.debug { "[SmcScannerJob] Waiting #{delay_between_instruments}s before next instrument..." }
        sleep(delay_between_instruments)
      end

      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )

      unless instrument
        Rails.logger.warn("[SmcScannerJob] Instrument not found for #{idx_cfg[:key]} (#{idx_cfg[:segment]}/#{idx_cfg[:sid]})")
        error_count += 1
        next
      end

      begin
        # Create engine with delay between candle fetches
        engine = Smc::BiasEngine.new(instrument, delay_seconds: delay_between_candle_fetches)
        decision = engine.decision # This will enqueue Telegram alert job if conditions met

        Rails.logger.info("[SmcScannerJob] #{idx_cfg[:key]}: #{decision}")

        # If AI is enabled, get AI analysis and send notification (matching rake task behavior)
        if engine.ai_enabled?
          Rails.logger.info("[SmcScannerJob] Getting AI analysis for #{idx_cfg[:key]} #{decision} signal...")
          ai_analysis = engine.analyze_with_ai
          if ai_analysis.present?
            Rails.logger.info("[SmcScannerJob] AI Analysis for #{idx_cfg[:key]}:")
            Rails.logger.info(ai_analysis)

            # Send instant Telegram notification with AI analysis
            send_ai_analysis_telegram_notification(idx_cfg[:key], decision, ai_analysis)
          else
            Rails.logger.warn("[SmcScannerJob] AI analysis returned empty for #{idx_cfg[:key]}")
          end
        end

        success_count += 1
      rescue DhanHQ::RateLimitError => e
        Rails.logger.error("[SmcScannerJob] Rate limit error for #{idx_cfg[:key]}: #{e.message}")
        Rails.logger.info('[SmcScannerJob] Waiting 5 seconds before continuing...')
        sleep(5)
        error_count += 1
        next
      rescue StandardError => e
        Rails.logger.error("[SmcScannerJob] Error processing #{idx_cfg[:key]}: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        error_count += 1
        next
      end
    end

    Rails.logger.info("[SmcScannerJob] Scan completed: #{success_count} successful, #{error_count} errors")
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Fatal error: #{e.class} - #{e.message}")
    Rails.logger.debug { e.backtrace.first(10).join("\n") }
    raise
  end

  private

  def log_market_closed_status
    target_date = Market::Calendar.next_trading_day.strftime('%Y-%m-%d')
    session = Live::TimeRegimeService.closed_session_label
    Rails.logger.debug do
      "[SmcScannerJob] Running while market closed (session=#{session}, target=#{target_date})"
    end
  end

  # One DB lookup per index: load instrument once, then apply expiry filter.
  def build_indices_with_instruments(indices)
    return [] if indices.empty?

    max_days = max_expiry_days
    indices.filter_map do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )
      unless instrument
        Rails.logger.warn("[SmcScannerJob] Instrument not found for #{idx_cfg[:key]}")
        next
      end

      days = calculate_days_to_expiry(instrument)
      if days > max_days
        Rails.logger.info("[SmcScannerJob] Skipping #{idx_cfg[:key]}: expiry in #{days} days (> #{max_days})")
        next
      end

      [idx_cfg, instrument]
    end
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Error building index list: #{e.message}")
    indices_without_expiry_filter(indices)
  end

  def indices_without_expiry_filter(indices)
    indices.filter_map do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )
      unless instrument
        Rails.logger.warn("[SmcScannerJob] Instrument not found for #{idx_cfg[:key]}")
        next
      end

      [idx_cfg, instrument]
    end
  end

  def wait_between_instruments(index)
    return unless index.positive?
    sleep(2.0) # Delay between instruments to avoid rate limits
  end

  def process_index(idx_cfg, instrument)
    engine = Smc::BiasEngine.new(instrument, delay_seconds: 1.0)
    decision = engine.decision
    Rails.logger.info("[SmcScannerJob] #{idx_cfg[:key]}: #{decision}")

    process_ai_analysis(engine, idx_cfg, decision) if engine.ai_enabled?
    true
  rescue DhanHQ::RateLimitError => e
    Rails.logger.error("[SmcScannerJob] Rate limit for #{idx_cfg[:key]}: #{e.message}")
    sleep(5)
    false
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Error processing #{idx_cfg[:key]}: #{e.class} - #{e.message}")
    false
  end

  def process_ai_analysis(engine, idx_cfg, decision)
    Rails.logger.info("[SmcScannerJob] Getting AI analysis for #{idx_cfg[:key]}...")
    ai_analysis = engine.analyze_with_ai

    if ai_analysis.present?
      send_ai_analysis_telegram_notification(idx_cfg[:key], decision, ai_analysis)
    else
      Rails.logger.warn("[SmcScannerJob] AI analysis empty for #{idx_cfg[:key]}")
    end
  end

  def calculate_days_to_expiry(instrument)
    expiry_list = instrument.expiry_list
    return 999 unless expiry_list&.any?

    today = Time.zone.today

    # Parse expiry dates
    parsed_expiries = expiry_list.compact.filter_map do |raw|
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String
        begin
          Date.parse(raw)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end

    # Find nearest expiry >= today
    nearest_expiry = parsed_expiries.select { |date| date >= today }.min
    return 999 unless nearest_expiry

    (nearest_expiry - today).to_i
  rescue StandardError => e
    Rails.logger.warn("[SmcScannerJob] Error calculating expiry for #{instrument.symbol_name}: #{e.class} - #{e.message}")
    999 # Default to high value if calculation fails
  end

  # Get maximum expiry days from config (default: 7 days)
  def max_expiry_days
    config = AlgoConfig.fetch[:signals] || {}
    max_days = config[:max_expiry_days] || 7
    max_days.to_i
  rescue StandardError
    7 # Default to 7 days if config unavailable
  end

  # Send instant Telegram notification with AI analysis
  # Sends synchronously (not via background job) for immediate delivery
  # This matches the behavior of the rake task
  def send_ai_analysis_telegram_notification(index_key, decision, ai_analysis)
    return unless telegram_enabled?

    safe_analysis = ERB::Util.html_escape(ai_analysis.to_s)
    message = <<~MESSAGE
      🤖 <b>SMC AI Analysis: #{ERB::Util.html_escape(index_key)}</b>

      <b>Decision:</b> #{ERB::Util.html_escape(decision.to_s.upcase)}

      <b>AI Analysis:</b>
      #{safe_analysis}
    MESSAGE

    begin
      TelegramNotifier.send_message(message, parse_mode: 'HTML')
      Rails.logger.info("[SmcScannerJob] Sent AI analysis Telegram notification for #{index_key}")
    rescue StandardError => e
      Rails.logger.error("[SmcScannerJob] Failed to send AI analysis Telegram notification: #{e.class} - #{e.message}")
    end
  end

  def telegram_enabled?
    ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
  rescue StandardError
    false
  end

  def closed_market_session_label
    Live::TimeRegimeService.closed_session_label
  end

  # Filter indices by expiry - only keep indices with expiry <= max_expiry_days (default: 7 days)
  def filter_indices_by_expiry(indices)
    return indices if indices.empty?

    max_expiry_days = get_max_expiry_days
    today = Time.zone.today
    filtered = []

    indices.each do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )

      unless instrument
        Rails.logger.warn("[SmcScannerJob] Instrument not found for #{idx_cfg[:key]} - skipping expiry check")
        # Include if instrument not found (let it fail later with proper error)
        filtered << idx_cfg
        next
      end

      days_to_expiry = calculate_days_to_expiry(instrument)

      if days_to_expiry > max_expiry_days
        Rails.logger.info(
          "[SmcScannerJob] Skipping #{idx_cfg[:key]} - expiry in #{days_to_expiry} days " \
          "(> #{max_expiry_days} days limit)"
        )
        next
      end

      filtered << idx_cfg
    end

    filtered
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Error filtering indices by expiry: #{e.class} - #{e.message}")
    # Return all indices if filtering fails (fail-safe)
    indices
  end

  # Calculate days to expiry for an instrument
  def calculate_days_to_expiry(instrument)
    expiry_list = instrument.expiry_list
    return 999 unless expiry_list&.any?

    today = Time.zone.today

    # Parse expiry dates
    parsed_expiries = expiry_list.compact.filter_map do |raw|
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String
        begin
          Date.parse(raw)
        rescue ArgumentError
          nil
        end
      else
        nil
      end
    end

    # Find nearest expiry >= today
    nearest_expiry = parsed_expiries.select { |date| date >= today }.min
    return 999 unless nearest_expiry

    (nearest_expiry - today).to_i
  rescue StandardError => e
    Rails.logger.warn("[SmcScannerJob] Error calculating expiry for #{instrument.symbol_name}: #{e.class} - #{e.message}")
    999 # Default to high value if calculation fails
  end

  # Get maximum expiry days from config (default: 7 days)
  def get_max_expiry_days
    config = AlgoConfig.fetch[:signals] || {}
    max_days = config[:max_expiry_days] || 7
    max_days.to_i
  rescue StandardError
    7 # Default to 7 days if config unavailable
  end
end

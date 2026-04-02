# frozen_string_literal: true

require_relative '../../lib/telegram_notifier'

# Background job to run SMC scanner for all configured indices
class SmcScannerJob < ApplicationJob
  queue_as :background

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 3

  def perform
    Rails.logger.info('[SmcScannerJob] Starting SMC scan...')

    log_market_closed_status if TradingSession::Service.market_closed?

    indices = IndexConfigLoader.load_indices
    filtered_indices = filter_indices_by_expiry(indices)
    Rails.logger.info("[SmcScannerJob] Scanning #{filtered_indices.size} indices...")

    indices_with_instruments = fetch_instruments(filtered_indices)
    
    success_count = 0
    error_count = 0

    indices_with_instruments.each_with_index do |(idx_cfg, instrument), index|
      wait_between_instruments(index)
      process_index(idx_cfg, instrument) ? success_count += 1 : error_count += 1
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

  def fetch_instruments(indices)
    indices.filter_map do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(security_id: idx_cfg[:sid].to_s, segment_code: idx_cfg[:segment])
      
      if instrument
        [idx_cfg, instrument]
      else
        Rails.logger.warn("[SmcScannerJob] Instrument not found for #{idx_cfg[:key]}")
        nil
      end
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

  def filter_indices_by_expiry(indices)
    return indices if indices.empty?

    max_days = max_expiry_days
    indices.select do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(security_id: idx_cfg[:sid].to_s, segment_code: idx_cfg[:segment])
      next true unless instrument

      days = calculate_days_to_expiry(instrument)
      if days > max_days
        Rails.logger.info("[SmcScannerJob] Skipping #{idx_cfg[:key]}: expiry in #{days} days (> #{max_days})")
        false
      else
        true
      end
    end
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Error filtering: #{e.message}")
    indices
  end

  def calculate_days_to_expiry(instrument)
    expiry_list = instrument.expiry_list
    return 999 unless expiry_list&.any?

    today = Time.zone.today
    parsed_expiries = expiry_list.compact.filter_map do |raw|
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String
        Date.parse(raw) rescue nil
      end
    end

    nearest_expiry = parsed_expiries.select { |date| date >= today }.min
    return 999 unless nearest_expiry

    (nearest_expiry - today).to_i
  rescue StandardError
    999
  end

  def max_expiry_days
    config = AlgoConfig.fetch[:signals] || {}
    (config[:max_expiry_days] || 7).to_i
  rescue StandardError
    7
  end

  def send_ai_analysis_telegram_notification(index_key, decision, ai_analysis)
    return unless telegram_enabled?

    message = <<~MESSAGE
      🤖 <b>SMC AI Analysis: #{index_key}</b>

      <b>Decision:</b> #{decision.to_s.upcase}

      <b>AI Analysis:</b>
      #{ai_analysis}
    MESSAGE

    TelegramNotifier.send_message(message, parse_mode: 'HTML')
    Rails.logger.info("[SmcScannerJob] Sent AI analysis Telegram notification for #{index_key}")
  rescue StandardError => e
    Rails.logger.error("[SmcScannerJob] Failed to send AI analysis: #{e.message}")
  end

  def telegram_enabled?
    ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
  end
end

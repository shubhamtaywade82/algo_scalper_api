# frozen_string_literal: true

# Background job to run SMC scanner for all configured indices
class SmcScannerJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform
    Rails.logger.info('[SmcScannerJob] Starting SMC scan...')

    indices = IndexConfigLoader.load_indices
    Rails.logger.info("[SmcScannerJob] Scanning #{indices.size} indices...")

    success_count = 0
    error_count = 0

    indices.each_with_index do |idx_cfg, index|
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

  # Delay between API calls to avoid rate limits (DH-904)
  def delay_between_instruments
    2.0 # seconds
  end

  def delay_between_candle_fetches
    1.0 # seconds
  end
end

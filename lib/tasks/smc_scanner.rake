# Delay between API calls to avoid rate limits (DH-904)
DELAY_BETWEEN_INSTRUMENTS = 2.0 # seconds
DELAY_BETWEEN_CANDLE_FETCHES = 1.0 # seconds

namespace :smc do
  desc 'Run SMC/AVRZ analysis for all configured indices'
  task scan: :environment do
    indices = IndexConfigLoader.load_indices
    Rails.logger.info("[SMCSanner] Starting scan for #{indices.size} indices...")

    indices.each_with_index do |idx_cfg, index|
      # Add delay between instruments (except first one)
      if index.positive?
        Rails.logger.debug { "[SMCSanner] Waiting #{DELAY_BETWEEN_INSTRUMENTS}s before next instrument..." }
        sleep(DELAY_BETWEEN_INSTRUMENTS)
      end

      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )
      unless instrument
        Rails.logger.warn("[SMCSanner] Instrument not found for #{idx_cfg[:key]} (#{idx_cfg[:segment]}/#{idx_cfg[:sid]})")
        next
      end

      begin
        # Create engine with delay between candle fetches
        engine = Smc::BiasEngine.new(instrument, delay_seconds: DELAY_BETWEEN_CANDLE_FETCHES)
        decision = engine.decision # This will send Telegram alert if conditions met

        Rails.logger.info("[SMCSanner] #{idx_cfg[:key]}: #{decision}")

        # If AI is enabled and we have a valid signal, get AI analysis
        if engine.ai_enabled? # && %i[call put].include?(decision)
          Rails.logger.info("[SMCSanner] Getting AI analysis for #{idx_cfg[:key]} #{decision} signal...")
          ai_analysis = engine.analyze_with_ai
          if ai_analysis.present?
            Rails.logger.info("[SMCSanner] AI Analysis for #{idx_cfg[:key]}:")
            Rails.logger.info(ai_analysis)
          else
            Rails.logger.warn("[SMCSanner] AI analysis returned empty for #{idx_cfg[:key]}")
          end
        end
      rescue DhanHQ::RateLimitError => e
        Rails.logger.error("[SMCSanner] Rate limit error for #{idx_cfg[:key]}: #{e.message}")
        Rails.logger.info('[SMCSanner] Waiting 5 seconds before continuing...')
        sleep(5)
        next
      rescue StandardError => e
        Rails.logger.error("[SMCSanner] Error processing #{idx_cfg[:key]}: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        next
      end
    end

    Rails.logger.info('[SMCSanner] Scan completed')
  end
end

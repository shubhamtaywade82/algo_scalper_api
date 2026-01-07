# Delay between API calls to avoid rate limits (DH-904)
DELAY_BETWEEN_INSTRUMENTS = 2.0 # seconds
DELAY_BETWEEN_CANDLE_FETCHES = 1.0 # seconds

namespace :smc do
  desc 'Run SMC/AVRZ analysis for all configured indices (or specific index if INDEX_KEY is provided)'
  desc 'Usage: rake smc:scan                    # Scan all indices'
  desc '       rake smc:scan[INDEX_KEY]         # Scan specific index (e.g., rake smc:scan[NIFTY])'
  task :scan, [:index_key] => :environment do |_t, args|
    indices = IndexConfigLoader.load_indices
    Rails.logger.info("[SMCSanner] Loaded #{indices.size} indices from config...")

    # Filter by specific index if provided
    if args[:index_key].present?
      index_key = args[:index_key].to_s.upcase
      indices = indices.select { |idx| (idx[:key] || idx['key']).to_s.upcase == index_key }
      if indices.empty?
        Rails.logger.error("[SMCSanner] Index '#{index_key}' not found in configured indices")
        Rails.logger.info("[SMCSanner] Available indices: #{IndexConfigLoader.load_indices.map { |i| i[:key] || i['key'] }.compact.join(', ')}")
        exit 1
      end
      Rails.logger.info("[SMCSanner] Filtered to specific index: #{index_key}")
    end

    # Filter indices by expiry (only analyze indices with expiry <= 7 days)
    filtered_indices = filter_indices_by_expiry(indices)
    Rails.logger.info("[SMCSanner] Scanning #{filtered_indices.size} indices (after expiry filter)...")

    filtered_indices.each_with_index do |idx_cfg, index|
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

  # Helper methods for expiry filtering (defined within namespace)
  # Filter indices by expiry - only keep indices with expiry <= max_expiry_days (default: 7 days)
  def filter_indices_by_expiry(indices)
    return indices if indices.empty?

    max_expiry_days = get_max_expiry_days
    filtered = []

    indices.each do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )

      unless instrument
        Rails.logger.warn("[SMCSanner] Instrument not found for #{idx_cfg[:key]} - skipping expiry check")
        # Include if instrument not found (let it fail later with proper error)
        filtered << idx_cfg
        next
      end

      days_to_expiry = calculate_days_to_expiry(instrument)

      if days_to_expiry > max_expiry_days
        Rails.logger.info(
          "[SMCSanner] Skipping #{idx_cfg[:key]} - expiry in #{days_to_expiry} days " \
          "(> #{max_expiry_days} days limit)"
        )
        next
      end

      filtered << idx_cfg
    end

    filtered
  rescue StandardError => e
    Rails.logger.error("[SMCSanner] Error filtering indices by expiry: #{e.class} - #{e.message}")
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
    Rails.logger.warn("[SMCSanner] Error calculating expiry for #{instrument.symbol_name}: #{e.class} - #{e.message}")
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

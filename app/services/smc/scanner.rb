# frozen_string_literal: true

module Smc
  # SMC + AVRZ Scanner service that runs periodically
  # Integrates with TradingSystem::Supervisor for lifecycle management
  # Runs continuously when market is open, skips cycles when market is closed
  class Scanner
    # Default period: 5 minutes (300 seconds)
    # Can be overridden via ENV['SMC_SCANNER_PERIOD'] or config
    DEFAULT_PERIOD = 300
    INTER_INDEX_DELAY = 2.0 # seconds between processing indices
    DELAY_BETWEEN_CANDLE_FETCHES = 1.0 # seconds between candle fetches

    def initialize(period: nil)
      @period = period || period_from_config || period_from_env || DEFAULT_PERIOD
      @running = false
      @thread = nil
      @mutex = Mutex.new
    end

    def start
      return if @running

      @mutex.synchronize do
        return if @running

        @running = true
      end

      begin
        indices = IndexConfigLoader.load_indices
      rescue StandardError => e
        Rails.logger.error("[Smc::Scanner] Failed to load indices: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        @mutex.synchronize { @running = false }
        return
      end

      if indices.empty?
        Rails.logger.warn('[Smc::Scanner] No indices configured - scanner will not process any signals')
        @mutex.synchronize { @running = false }
        return
      end

      @thread = Thread.new do
        Thread.current.name = 'smc-scanner'

        loop do
          break unless @running

          begin
            # Early exit if market is closed - avoid unnecessary processing
            if TradingSession::Service.market_closed?
              Rails.logger.debug('[Smc::Scanner] Market closed - skipping cycle')
              sleep @period
              next
            end

            # Filter indices by expiry and process
            filtered_indices = filter_indices_by_expiry(indices)

            if filtered_indices.empty?
              Rails.logger.debug('[Smc::Scanner] No indices with valid expiry - skipping cycle')
              sleep @period
              next
            end

            Rails.logger.info("[Smc::Scanner] Starting scan cycle for #{filtered_indices.size} indices...")

            filtered_indices.each_with_index do |idx_cfg, index|
              break unless @running

              # Re-check market status before each index (market might close during processing)
              if TradingSession::Service.market_closed?
                Rails.logger.debug('[Smc::Scanner] Market closed during processing - stopping cycle')
                break
              end

              sleep(index.zero? ? 0 : INTER_INDEX_DELAY)
              process_index(idx_cfg)
            end

            Rails.logger.debug { "[Smc::Scanner] Scan cycle completed, sleeping for #{@period}s" }
          rescue StandardError => e
            Rails.logger.error("[Smc::Scanner] Cycle error: #{e.class} - #{e.message}")
            Rails.logger.debug { e.backtrace.first(5).join("\n") }
          end

          sleep @period
        end
      end
    end

    def stop
      @mutex.synchronize do
        return unless @running

        @running = false
      end

      return unless @thread

      # Give thread 2 seconds to finish gracefully
      unless @thread.join(2)
        Rails.logger.warn('[Smc::Scanner] Thread did not finish gracefully, forcing termination')
        @thread.kill if @thread.alive?
      end

      @thread = nil
      Rails.logger.info('[Smc::Scanner] Stopped successfully')
    rescue StandardError => e
      Rails.logger.error("[Smc::Scanner] Error during stop: #{e.class} - #{e.message}")
      @thread&.kill if @thread&.alive?
      @thread = nil
      raise
    end

    def running?
      @mutex.synchronize { @running }
    end

    private

    def process_index(index_cfg)
      instrument = Instrument.find_by_sid_and_segment(
        security_id: index_cfg[:sid].to_s,
        segment_code: index_cfg[:segment]
      )

      unless instrument
        Rails.logger.warn("[Smc::Scanner] Instrument not found for #{index_cfg[:key]} (#{index_cfg[:segment]}/#{index_cfg[:sid]})")
        return
      end

      begin
        # Create engine with delay between candle fetches
        engine = Smc::BiasEngine.new(instrument, delay_seconds: DELAY_BETWEEN_CANDLE_FETCHES)
        decision = engine.decision # This will enqueue Telegram alert job if conditions met

        Rails.logger.info("[Smc::Scanner] #{index_cfg[:key]}: #{decision}")

        # If AI is enabled, get AI analysis (async via job)
        if engine.ai_enabled? && %i[call put].include?(decision)
          Rails.logger.debug { "[Smc::Scanner] AI enabled for #{index_cfg[:key]} #{decision} signal - analysis will be sent via background job" }
        end
      rescue DhanHQ::RateLimitError => e
        Rails.logger.error("[Smc::Scanner] Rate limit error for #{index_cfg[:key]}: #{e.message}")
        Rails.logger.info('[Smc::Scanner] Waiting 5 seconds before continuing...')
        sleep(5)
      rescue StandardError => e
        Rails.logger.error("[Smc::Scanner] Error processing #{index_cfg[:key]}: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
      end
    end

    # Filter indices by expiry - only keep indices with expiry <= max_expiry_days (default: 7 days)
    def filter_indices_by_expiry(indices)
      return indices if indices.empty?

      max_expiry_days = max_expiry_days_from_config
      filtered = []

      indices.each do |idx_cfg|
        instrument = Instrument.find_by_sid_and_segment(
          security_id: idx_cfg[:sid].to_s,
          segment_code: idx_cfg[:segment]
        )

        unless instrument
          Rails.logger.warn("[Smc::Scanner] Instrument not found for #{idx_cfg[:key]} - skipping expiry check")
          filtered << idx_cfg
          next
        end

        days_to_expiry = calculate_days_to_expiry(instrument)

        if days_to_expiry > max_expiry_days
          Rails.logger.debug do
            "[Smc::Scanner] Skipping #{idx_cfg[:key]} - expiry in #{days_to_expiry} days " \
              "(> #{max_expiry_days} days limit)"
          end
          next
        end

        filtered << idx_cfg
      end

      filtered
    rescue StandardError => e
      Rails.logger.error("[Smc::Scanner] Error filtering indices by expiry: #{e.class} - #{e.message}")
      indices # Return all indices if filtering fails (fail-safe)
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
        end
      end

      # Find nearest expiry >= today
      nearest_expiry = parsed_expiries.select { |date| date >= today }.min
      return 999 unless nearest_expiry

      (nearest_expiry - today).to_i
    rescue StandardError => e
      Rails.logger.warn("[Smc::Scanner] Error calculating expiry for #{instrument.symbol_name}: #{e.class} - #{e.message}")
      999 # Default to high value if calculation fails
    end

    # Get maximum expiry days from config (default: 7 days)
    def max_expiry_days_from_config
      config = AlgoConfig.fetch[:signals] || {}
      max_days = config[:max_expiry_days] || 7
      max_days.to_i
    rescue StandardError
      7 # Default to 7 days if config unavailable
    end

    # Get scanner period from config
    def period_from_config
      config = AlgoConfig.fetch[:smc] || {}
      period_seconds = config[:scanner_period_seconds]
      return nil unless period_seconds

      period_seconds.to_i
    rescue StandardError
      nil
    end

    # Get scanner period from environment variable
    def period_from_env
      return nil unless ENV['SMC_SCANNER_PERIOD']

      ENV['SMC_SCANNER_PERIOD'].to_i
    rescue StandardError
      nil
    end
  end
end

# frozen_string_literal: true

module Signal
  # rubocop:disable Metrics/ClassLength
  class Scheduler
    DEFAULT_PERIOD = 30 # seconds
    INTER_INDEX_DELAY = 5 # seconds between processing indices

    def initialize(period: DEFAULT_PERIOD, data_provider: nil)
      @period = period
      @running = false
      @thread  = nil
      @mutex   = Mutex.new
      @data_provider = data_provider || default_provider
      @expiry_cache = {}
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
        Rails.logger.error("[SignalScheduler] Failed to load indices: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        @mutex.synchronize { @running = false }
        return
      end

      if indices.empty?
        Rails.logger.warn('[SignalScheduler] No indices configured - scheduler will not process any signals')
        @mutex.synchronize { @running = false }
        return
      end

      @thread = Thread.new do
        Thread.current.name = 'signal-scheduler'

        loop do
          break unless @running

          begin
            # Early exit if market is closed - avoid unnecessary processing
            if TradingSession::Service.market_closed?
              Rails.logger.debug('[SignalScheduler] Market closed - skipping cycle')
              sleep @period
              next
            end

            # Reorder indices by expiry proximity (closer expiry = higher priority)
            ordered_indices = reorder_indices_by_expiry(indices)

            ordered_indices.each_with_index do |idx_cfg, idx|
              break unless @running

              # Re-check market status before each index (market might close during processing)
              if TradingSession::Service.market_closed?
                Rails.logger.debug('[SignalScheduler] Market closed during processing - stopping cycle')
                break
              end

              sleep(idx.zero? ? 0 : INTER_INDEX_DELAY)
              process_index(idx_cfg)
            end
          rescue StandardError => e
            Rails.logger.error("[SignalScheduler] Cycle error: #{e.class} - #{e.message}")
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
        # Thread didn't finish in time, force kill
        Rails.logger.warn('[SignalScheduler] Thread did not finish gracefully, forcing termination')
        @thread.kill if @thread.alive?
      end

      @thread = nil
      Rails.logger.info('[SignalScheduler] Stopped successfully')
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Error during stop: #{e.class} - #{e.message}")
      # Ensure cleanup even if there's an error
      @thread&.kill if @thread&.alive?
      @thread = nil
      raise
    end

    def running?
      @mutex.synchronize { @running }
    end

    private

    def process_index(index_cfg)
      # Use run_for() which includes full No-Trade Engine integration
      # run_for() handles: Phase 1 pre-check, signal generation, strike selection, Phase 2 validation, and entry
      Signal::Engine.run_for(index_cfg)

      # NOTE: run_for() handles entry internally, so we don't need process_signal() here
      # The old flow (evaluate_supertrend_signal + process_signal) is bypassed
      # This ensures No-Trade Engine validation is always applied
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] process_index error #{index_cfg[:key]}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
    end

    def evaluate_strategy(index_cfg, strategy, candidate)
      engine = strategy[:engine_class].new(
        index: index_cfg,
        config: strategy[:config],
        option_candidate: candidate
      )

      engine.evaluate
    rescue StandardError => e
      Rails.logger.error(
        "[SignalScheduler] Strategy #{strategy[:key]} evaluation failed: #{e.class} - #{e.message}"
      )
      nil
    end

    def determine_direction(index_cfg)
      direction = index_cfg[:direction] || AlgoConfig.fetch.dig(:strategy, :direction) || :bullish
      direction.to_s.downcase.to_sym
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Failed to determine direction: #{e.class} - #{e.message}")
      :bullish # Default fallback
    end

    def process_signal(index_cfg, signal)
      pick = build_pick_from_signal(signal)
      direction_override = signal.dig(:meta, :direction)&.to_sym
      direction = direction_override || determine_direction(index_cfg)
      multiplier = signal[:meta][:multiplier] || 1

      entry_successful = Entries::EntryGuard.try_enter(
        index_cfg: index_cfg,
        pick: pick,
        direction: direction,
        scale_multiplier: multiplier,
        permission: :scale_ready
      )

      if entry_successful
        Rails.logger.info(
          "[SignalScheduler] Entry successful for #{index_cfg[:key]}: #{signal[:meta][:candidate_symbol]} " \
          "(direction: #{direction}, multiplier: #{multiplier})"
        )
      else
        Rails.logger.warn(
          "[SignalScheduler] EntryGuard rejected signal for #{index_cfg[:key]}: #{signal[:meta][:candidate_symbol]} " \
          "(direction: #{direction})"
        )
      end

      entry_successful
    end

    def build_pick_from_signal(signal)
      segment = signal[:segment] || signal[:exchange_segment]
      {
        segment: segment,
        security_id: signal[:security_id],
        symbol: signal[:meta][:candidate_symbol] || 'UNKNOWN',
        lot_size: signal[:meta][:lot_size] || 1,
        ltp: nil # Will be resolved by EntryGuard
      }
    end

    def default_provider
      Providers::DhanhqProvider.new
    rescue NameError
      nil
    end

    def evaluate_supertrend_signal(index_cfg)
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      unless instrument
        Rails.logger.warn("[SignalScheduler] Missing instrument for #{index_cfg[:key]}")
        return nil
      end

      # Path 1: Trend Scorer (Direction-First) - if enabled
      return evaluate_with_trend_scorer(index_cfg, instrument) if trend_scorer_enabled?

      # Path 2: Legacy Supertrend + ADX (default)
      evaluate_with_legacy_indicators(index_cfg, instrument)
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Signal evaluation failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    def evaluate_with_trend_scorer(index_cfg, _instrument)
      trend_result = Signal::TrendScorer.compute_direction(index_cfg: index_cfg)
      trend_score = trend_result[:trend_score]
      direction = trend_result[:direction]
      breakdown = trend_result[:breakdown]

      min_trend_score = signal_config.dig(:trend_scorer, :min_trend_score) || 14.0
      if trend_score.nil? || trend_score < min_trend_score || direction.nil?
        Rails.logger.debug do
          "[SignalScheduler] Skipping #{index_cfg[:key]} - trend_score=#{trend_score} " \
            "direction=#{direction} (min=#{min_trend_score}) " \
            "breakdown=#{breakdown.inspect}"
        end
        return nil
      end

      # Direction confirmed - proceed to chain analysis
      chain_cfg = AlgoConfig.fetch[:chain_analyzer] || {}
      candidate = select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_score)
      return nil unless candidate

      {
        segment: candidate[:segment],
        security_id: candidate[:security_id],
        reason: 'trend_scorer_direction',
        meta: {
          candidate_symbol: candidate[:symbol],
          lot_size: candidate[:lot_size] || candidate[:lot] || 1,
          direction: direction,
          trend_score: trend_score,
          source: 'trend_scorer',
          multiplier: 1
        }
      }
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] TrendScorer evaluation failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      nil
    end

    def evaluate_with_legacy_indicators(index_cfg, instrument)
      # NOTE: This method is DEPRECATED - process_index() now calls Signal::Engine.run_for() directly
      # Kept for backward compatibility if evaluate_supertrend_signal() is called elsewhere
      #
      # The new flow uses Signal::Engine.run_for() which includes:
      # - Phase 1: Quick No-Trade pre-check
      # - Signal generation (Supertrend + ADX)
      # - Strike selection
      # - Phase 2: Detailed No-Trade validation
      # - EntryGuard.try_enter()

      # For now, delegate to run_for() which has full No-Trade Engine integration
      Signal::Engine.run_for(index_cfg)
      nil # run_for() handles entry internally, return nil to indicate processed
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Legacy indicator evaluation failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      nil
    end

    def select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_score)
      analyzer = Options::ChainAnalyzer.new(
        index: index_cfg,
        data_provider: @data_provider,
        config: chain_cfg
      )

      limit = (chain_cfg[:max_candidates] || 3).to_i
      candidates = analyzer.select_candidates(limit: limit, direction: direction)
      return if candidates.blank?

      candidate = candidates.first.dup
      candidate[:trend_score] ||= trend_score
      candidate
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Chain analyzer selection failed: #{e.class} - #{e.message}")
      nil
    end

    def signal_config
      AlgoConfig.fetch[:signals] || {}
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Failed to load signal config: #{e.class} - #{e.message}")
      {}
    end

    def trend_scorer_enabled?
      flags = feature_flags

      # If enable_trend_scorer is explicitly set to false, disable TrendScorer regardless of legacy flag
      return false if flags[:enable_trend_scorer] == false

      # Otherwise, check enable_trend_scorer (new explicit toggle) OR enable_direction_before_chain (legacy)
      # Note: enable_direction_before_chain is deprecated but kept for backward compatibility
      flags[:enable_trend_scorer] == true || flags[:enable_direction_before_chain] == true
    end

    def feature_flags
      AlgoConfig.fetch[:feature_flags] || {}
    rescue StandardError
      {}
    end

    # Reorder indices by expiry proximity (closer expiry = processed first)
    # @param indices [Array<Hash>] Array of index configurations
    # @return [Array<Hash>] Indices sorted by expiry proximity (closest first)
    def reorder_indices_by_expiry(indices)
      return indices if indices.empty?

      # Cache expiry calculations (expiry dates don't change frequently)
      cache_key = indices.map { |i| i[:key].to_s }.sort.join(',')
      if @expiry_cache && @expiry_cache[cache_key] &&
         (Time.current - @expiry_cache[cache_key][:cached_at]) < 1.hour
        Rails.logger.debug { "[SignalScheduler] Using cached expiry order for: #{cache_key}" }
        return @expiry_cache[cache_key][:sorted_indices]
      end

      @expiry_cache ||= {}
      Rails.logger.debug { "[SignalScheduler] Calculating expiry order (cache miss) for: #{cache_key}" }
      today = Time.zone.today
      indexed_with_expiry = indices.filter_map do |idx_cfg|
        instrument = IndexInstrumentCache.instance.get_or_fetch(idx_cfg)
        if instrument
          expiry_list = instrument.expiry_list
          if expiry_list&.any?
            # Parse expiry dates and find nearest
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
            days_to_expiry = nearest_expiry ? (nearest_expiry - today).to_i : 999

            {
              index_cfg: idx_cfg,
              days_to_expiry: days_to_expiry,
              expiry_date: nearest_expiry
            }
          else
            Rails.logger.warn("[SignalScheduler] No expiry list for #{idx_cfg[:key]} - using default priority")
            { index_cfg: idx_cfg, days_to_expiry: 999, expiry_date: nil }
          end
        else
          Rails.logger.warn("[SignalScheduler] No instrument found for #{idx_cfg[:key]} - using default priority")
          { index_cfg: idx_cfg, days_to_expiry: 999, expiry_date: nil }
        end
      rescue StandardError => e
        Rails.logger.warn("[SignalScheduler] Error calculating expiry for #{idx_cfg[:key]}: #{e.class} - #{e.message}")
        { index_cfg: idx_cfg, days_to_expiry: 999, expiry_date: nil }
      end

      # Filter out indices with expiry > max_expiry_days (default: 7 days)
      max_expiry_days = get_max_expiry_days
      filtered = indexed_with_expiry.reject do |item|
        next false if item[:days_to_expiry] <= max_expiry_days

        Rails.logger.info(
          "[SignalScheduler] Skipping #{item[:index_cfg][:key]} - expiry in #{item[:days_to_expiry]} days " \
          "(> #{max_expiry_days} days limit)"
        )
        true
      end

      # Sort by days_to_expiry (ascending - closer expiry first)
      sorted = filtered.sort_by { |item| item[:days_to_expiry] }

      # Log the ordering for debugging
      if sorted.size > 1
        order_str = sorted.map do |item|
          expiry_info = item[:expiry_date] ? "#{item[:expiry_date].strftime('%Y-%m-%d')} (#{item[:days_to_expiry]}d)" : 'N/A'
          "#{item[:index_cfg][:key]}: #{expiry_info}"
        end.join(' → ')
        Rails.logger.debug { "[SignalScheduler] Processing order (by expiry proximity): #{order_str}" }
      end

      # Return just the index configs in sorted order
      sorted_indices = sorted.map { |item| item[:index_cfg] }

      # Cache result
      @expiry_cache[cache_key] = {
        sorted_indices: sorted_indices,
        cached_at: Time.current
      }

      sorted_indices
    end

    # Get maximum expiry days from config (default: 7 days)
    # Indices with expiry > this limit will be skipped
    def get_max_expiry_days
      config = AlgoConfig.fetch[:signals] || {}
      max_days = config[:max_expiry_days] || 7
      max_days.to_i
    rescue StandardError
      7 # Default to 7 days if config unavailable
    end
  end
  # rubocop:enable Metrics/ClassLength
end

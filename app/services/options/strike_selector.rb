# frozen_string_literal: true

module Options
  # StrikeSelector for NEMESIS V3 architecture
  # Uses existing DerivativeChainAnalyzer and applies index-specific rules
  # Returns normalized instrument hash for EntryManager/Orders::Placer
  # Enhanced with ATM/1OTM/2OTM selection based on trend strength
  # rubocop:disable Metrics/ClassLength
  class StrikeSelector
    class SelectionError < StandardError; end

    # Trend score thresholds for OTM depth
    # Higher trend scores allow deeper OTM strikes
    TREND_THRESHOLD_1OTM = 12.0  # Allow 1OTM if trend_score >= 12
    TREND_THRESHOLD_2OTM = 18.0  # Allow 2OTM if trend_score >= 18

    def initialize(tick_cache: nil, premium_filter: nil)
      @tick_cache = tick_cache || Live::TickCache
      @premium_filter_class = premium_filter || PremiumFilter
    end

    # Select best strike for given index & direction
    # @param index_key [String, Symbol] Index key (NIFTY, BANKNIFTY, SENSEX)
    # @param direction [Symbol] :bullish (CE) or :bearish (PE)
    # @param expiry [String, Date, nil] Expiry date (nil = auto-select nearest)
    # @param trend_score [Float, nil] Trend score from TrendScorer (0-21)
    # @param config [Hash] Additional config for DerivativeChainAnalyzer
    # @return [Hash, nil] Normalized instrument hash or nil if no valid strike
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def select(index_key:, direction:, expiry: nil, trend_score: nil, config: {})
      index_key = normalize_index(index_key)
      rules = load_rules_for(index_key)

      # Determine allowed OTM depth based on trend score
      max_otm_depth = calculate_max_otm_depth(trend_score)

      # Get spot price for ATM calculation
      spot = get_spot_price(index_key)
      return nil unless spot&.positive?

      # Calculate ATM strike
      atm_strike = rules.atm(spot)

      # Use existing DerivativeChainAnalyzer
      analyzer = DerivativeChainAnalyzer.new(
        index_key: index_key,
        expiry: expiry,
        config: config
      )

      # Get candidates (already scored and sorted)
      # Get more candidates for filtering by strike distance
      candidates = analyzer.select_candidates(limit: 10, direction: direction)

      if candidates.empty?
        Rails.logger.warn("[Options::StrikeSelector] No candidates from DerivativeChainAnalyzer for #{index_key}")
        return nil
      end

      # Filter candidates by strike distance (ATM/1OTM/2OTM only)
      allowed_strikes = calculate_allowed_strikes(atm_strike, max_otm_depth, direction, rules)
      filtered_candidates = filter_by_strike_distance(candidates, allowed_strikes)

      if filtered_candidates.empty?
        Rails.logger.warn("[Options::StrikeSelector] No candidates within allowed strike distance for #{index_key} (ATM+#{max_otm_depth}OTM)")
        return nil
      end

      # Apply PremiumFilter validation
      premium_filter = @premium_filter_class.new(index_key: index_key)

      # Apply index-specific rules and premium filter to candidates
      filtered_candidates.each do |candidate|
        next unless candidate_valid?(candidate, rules, premium_filter)

        # Resolve LTP from tick cache or candidate
        ltp = resolve_ltp(candidate)
        next unless ltp&.positive?

        # Return normalized instrument hash
        return build_instrument_hash(candidate, index_key, ltp, rules, max_otm_depth)
      end

      Rails.logger.warn("[Options::StrikeSelector] No valid strike passed validation for #{index_key}")
      nil
    rescue SelectionError => e
      Rails.logger.error("[Options::StrikeSelector] Selection error: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[Options::StrikeSelector] Unexpected error: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def normalize_index(index)
      index.to_s.strip.upcase
    end

    def load_rules_for(index_key)
      case index_key.to_s.upcase
      when 'NIFTY' then IndexRules::Nifty.new
      when 'BANKNIFTY' then IndexRules::Banknifty.new
      when 'SENSEX' then IndexRules::Sensex.new
      else
        raise SelectionError, "Unknown index: #{index_key}"
      end
    end

    # Calculate maximum OTM depth allowed based on trend score
    # @param trend_score [Float, nil] Trend score (0-21)
    # @return [Integer] Maximum OTM depth: 0 (ATM only), 1 (ATM+1OTM), 2 (ATM+2OTM)
    # NOTE: Capped at 2OTM to prevent selecting strikes too far from ATM
    def calculate_max_otm_depth(trend_score)
      return 0 unless trend_score&.positive? # Default to ATM only if no trend score

      if trend_score >= TREND_THRESHOLD_2OTM
        2 # Allow up to 2OTM
      elsif trend_score >= TREND_THRESHOLD_1OTM
        1 # Allow up to 1OTM
      else
        0 # ATM only
      end
    end

    # Calculate allowed strikes based on ATM and max OTM depth
    # @param atm_strike [Float] ATM strike price
    # @param max_otm_depth [Integer] Maximum OTM depth (0, 1, or 2)
    # @param direction [Symbol] :bullish (CE) or :bearish (PE)
    # @param rules [IndexRules] Index rules instance
    # @return [Array<Float>] Array of allowed strike prices
    def calculate_allowed_strikes(atm_strike, max_otm_depth, direction, rules)
      strikes = [atm_strike]

      # Get strike increment from rules (e.g., 50 for NIFTY, 100 for BANKNIFTY)
      strike_increment = get_strike_increment(atm_strike, rules)

      # For bullish (CE): OTM = strikes above ATM
      # For bearish (PE): OTM = strikes below ATM
      if direction == :bullish
        strikes << (atm_strike + strike_increment) if max_otm_depth >= 1
        strikes << (atm_strike + (strike_increment * 2)) if max_otm_depth >= 2
      else # :bearish
        strikes << (atm_strike - strike_increment) if max_otm_depth >= 1
        strikes << (atm_strike - (strike_increment * 2)) if max_otm_depth >= 2
      end

      strikes
    end

    # Get strike increment for index (e.g., 50 for NIFTY, 100 for BANKNIFTY)
    # @param atm_strike [Float] ATM strike
    # @param rules [IndexRules] Index rules instance
    # @return [Integer] Strike increment
    def get_strike_increment(atm_strike, rules)
      # Use candidate_strikes to infer increment
      candidate_strikes = rules.candidate_strikes(atm_strike, nil)
      return 50 if candidate_strikes.size < 2 # Default fallback

      # Calculate increment from first two strikes
      (candidate_strikes[1] - candidate_strikes[0]).abs
    end

    # Filter candidates by strike distance from ATM
    # @param candidates [Array<Hash>] Candidate hashes with :strike key
    # @param allowed_strikes [Array<Float>] Allowed strike prices
    # @return [Array<Hash>] Filtered candidates
    def filter_by_strike_distance(candidates, allowed_strikes)
      candidates.select do |candidate|
        strike = candidate[:strike]&.to_f || candidate[:strike_price]&.to_f
        next false unless strike

        # Check if strike is in allowed list (use tolerance for float comparison)
        allowed_strikes.any? { |allowed| (strike - allowed).abs < 0.01 }
      end
    end

    # Get spot price for index
    # @param index_key [String] Index key
    # @return [Float, nil] Spot price
    def get_spot_price(index_key)
      index_cfg = AlgoConfig.fetch[:indices]&.find { |idx| idx[:key].to_s.upcase == index_key.to_s.upcase }
      return nil unless index_cfg

      segment = index_cfg[:segment]
      security_id = index_cfg[:sid]

      # Try tick cache first (fastest, no API rate limits)
      spot = @tick_cache.ltp(segment, security_id)
      return spot if spot&.positive?

      # Try Redis tick cache
      spot = Live::RedisTickCache.instance.fetch_tick(segment, security_id)&.dig(:ltp)&.to_f
      return spot if spot&.positive?

      # Fallback to API via Instrument.ltp() (same pattern as InstrumentHelpers)
      # This ensures we can get spot price even when WebSocket is not running
      begin
        instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: security_id.to_s)
        if instrument
          spot = instrument.ltp&.to_f
          return spot if spot&.positive?
        end
      rescue StandardError => e
        Rails.logger.debug("[Options::StrikeSelector] API fallback failed for #{index_key}: #{e.message}")
      end

      nil
    end

    def candidate_valid?(candidate, rules, premium_filter)
      # Validate liquidity
      return false unless rules.valid_liquidity?(candidate)

      # Validate spread
      return false unless rules.valid_spread?(candidate)

      # Validate premium
      return false unless rules.valid_premium?(candidate)

      # Apply PremiumFilter validation
      return false unless premium_filter.valid?(candidate)

      true
    end

    def resolve_ltp(candidate)
      # Try tick cache first
      segment = candidate[:segment]
      security_id = candidate[:security_id]

      if segment.present? && security_id.present?
        cached_ltp = @tick_cache.ltp(segment, security_id)
        return cached_ltp if cached_ltp&.positive?
      end

      # Fallback to candidate LTP
      candidate[:ltp]&.to_f || candidate[:last_price]&.to_f
    end

    def build_instrument_hash(candidate, index_key, ltp, rules, max_otm_depth)
      {
        index: index_key,
        exchange_segment: candidate[:segment],
        security_id: candidate[:security_id].to_s,
        strike: candidate[:strike]&.to_i || candidate[:strike_price]&.to_i,
        option_type: candidate[:type],
        ltp: ltp.to_f,
        lot_size: candidate[:lot_size] || rules.lot_size,
        spot: nil, # Can be fetched separately if needed
        multiplier: rules.multiplier,
        derivative: candidate[:derivative],
        derivative_id: candidate[:derivative_id],
        symbol: candidate[:symbol],
        iv: candidate[:iv],
        oi: candidate[:oi],
        score: candidate[:score],
        reason: candidate[:reason],
        otm_depth: calculate_otm_depth(candidate, index_key, rules),
        max_otm_allowed: max_otm_depth
      }
    end

    # Calculate OTM depth for selected strike (0=ATM, 1=1OTM, 2=2OTM)
    # @param candidate [Hash] Selected candidate
    # @param index_key [String] Index key
    # @param rules [IndexRules] Index rules instance
    # @return [Integer] OTM depth (0, 1, or 2)
    def calculate_otm_depth(candidate, index_key, rules)
      strike = candidate[:strike]&.to_f || candidate[:strike_price]&.to_f
      return 0 unless strike

      spot = get_spot_price(index_key)
      return 0 unless spot&.positive?

      atm_strike = rules.atm(spot)
      strike_increment = get_strike_increment(atm_strike, rules)

      diff = (strike - atm_strike).abs
      if diff < 0.01
        0 # ATM
      elsif diff <= (strike_increment + 0.01)
        1 # 1OTM
      elsif diff <= ((strike_increment * 2) + 0.01)
        2 # 2OTM
      else
        -1 # Deeper OTM (should not happen after filtering)
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end

# frozen_string_literal: true

module Options
  # StrikeSelector for NEMESIS V3 architecture
  # Uses existing DerivativeChainAnalyzer and applies index-specific rules
  # Returns normalized instrument hash for EntryManager/Orders::Placer
  class StrikeSelector
    class SelectionError < StandardError; end

    def initialize(tick_cache: nil)
      @tick_cache = tick_cache || Live::TickCache
    end

    # Select best strike for given index & direction
    # @param index_key [String, Symbol] Index key (NIFTY, BANKNIFTY, SENSEX)
    # @param direction [Symbol] :bullish (CE) or :bearish (PE)
    # @param expiry [String, Date, nil] Expiry date (nil = auto-select nearest)
    # @param config [Hash] Additional config for DerivativeChainAnalyzer
    # @return [Hash, nil] Normalized instrument hash or nil if no valid strike
    def select(index_key:, direction:, expiry: nil, config: {})
      index_key = normalize_index(index_key)
      rules = load_rules_for(index_key)

      # Use existing DerivativeChainAnalyzer
      analyzer = DerivativeChainAnalyzer.new(
        index_key: index_key,
        expiry: expiry,
        config: config
      )

      # Get candidates (already scored and sorted)
      candidates = analyzer.select_candidates(limit: 5, direction: direction)

      if candidates.empty?
        Rails.logger.warn("[Options::StrikeSelector] No candidates from DerivativeChainAnalyzer for #{index_key}")
        return nil
      end

      # Apply index-specific rules to candidates
      candidates.each do |candidate|
        next unless candidate_valid?(candidate, rules)

        # Resolve LTP from tick cache or candidate
        ltp = resolve_ltp(candidate)
        next unless ltp&.positive?

        # Return normalized instrument hash
        return build_instrument_hash(candidate, index_key, ltp, rules)
      end

      Rails.logger.warn("[Options::StrikeSelector] No valid strike passed index rules for #{index_key}")
      nil
    rescue SelectionError => e
      Rails.logger.error("[Options::StrikeSelector] Selection error: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[Options::StrikeSelector] Unexpected error: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

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

    def candidate_valid?(candidate, rules)
      # Validate liquidity
      return false unless rules.valid_liquidity?(candidate)

      # Validate spread
      return false unless rules.valid_spread?(candidate)

      # Validate premium
      return false unless rules.valid_premium?(candidate)

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
      candidate[:ltp]&.to_f
    end

    def build_instrument_hash(candidate, index_key, ltp, rules)
      {
        index: index_key,
        exchange_segment: candidate[:segment],
        security_id: candidate[:security_id].to_s,
        strike: candidate[:strike].to_i,
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
        reason: candidate[:reason]
      }
    end
  end
end

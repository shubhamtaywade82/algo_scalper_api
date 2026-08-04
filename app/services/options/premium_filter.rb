# frozen_string_literal: true

module Options
  # Premium filter service for NEMESIS V3
  # Enforces index-specific premium bands and liquidity/spread checks
  # Used by StrikeSelector to validate option candidates
  class PremiumFilter
    attr_reader :index_key, :rules

    def initialize(index_key:)
      @index_key = index_key.to_sym
      @rules = load_rules_for(@index_key)
      raise ArgumentError, "Unknown index: #{@index_key}" unless @rules
    end

    # Validate if candidate passes premium, liquidity, and spread checks
    # @param candidate [Hash] Candidate with keys: :premium, :ltp, :bid, :ask, :volume, :oi
    # @return [Boolean] True if candidate passes all checks
    def valid?(candidate)
      return false unless candidate.is_a?(Hash)

      premium_in_band?(candidate[:premium] || candidate[:ltp]) &&
        liquidity_ok?(candidate) &&
        spread_ok?(candidate)
    rescue StandardError => e
      Rails.logger.error("[PremiumFilter] Validation error for #{@index_key}: #{e.class} - #{e.message}")
      false
    end

    # Get validation details (for debugging/logging)
    # @param candidate [Hash] Candidate to validate
    # @return [Hash] Validation details with reasons
    def validate_with_details(candidate)
      return { valid: false, reason: 'invalid_candidate' } unless candidate.is_a?(Hash)

      premium = candidate[:premium] || candidate[:ltp]
      details = {
        premium_check: premium_in_band?(premium),
        liquidity_check: liquidity_ok?(candidate),
        spread_check: spread_ok?(candidate),
        premium_value: premium,
        min_premium: @rules.class::MIN_PREMIUM,
        volume: candidate[:volume],
        min_volume: @rules.class::MIN_VOLUME,
        spread_pct: calculate_spread(candidate[:bid], candidate[:ask], candidate[:ltp]),
        max_spread_pct: @rules.class::MAX_SPREAD_PCT
      }

      details[:valid] = details[:premium_check] && details[:liquidity_check] && details[:spread_check]
      details[:reason] = determine_reason(details)

      details
    end

    private

    # Load index-specific rules
    # @param index_key [Symbol] Index key (e.g., :NIFTY, :BANKNIFTY, :SENSEX)
    # @return [Class] IndexRules class instance
    def load_rules_for(index_key)
      case index_key.to_s.upcase
      when 'NIFTY' then IndexRules::Nifty.new
      when 'BANKNIFTY' then IndexRules::Banknifty.new
      when 'SENSEX' then IndexRules::Sensex.new
      else
        Rails.logger.error("[PremiumFilter] Unknown index: #{index_key}")
        nil
      end
    end

    # Check if premium is within acceptable band
    # @param premium [Float, nil] Premium/LTP value
    # @return [Boolean] True if premium >= min_premium
    def premium_in_band?(premium)
      return false unless premium&.positive?

      premium >= @rules.class::MIN_PREMIUM
    end

    # Check if candidate has sufficient liquidity
    # @param candidate [Hash] Candidate with :volume and :oi
    # @return [Boolean] True if volume >= min_volume
    def liquidity_ok?(candidate)
      volume = candidate[:volume] || candidate[:oi] || 0
      volume.to_i >= @rules.class::MIN_VOLUME
    end

    # Check if spread is within acceptable range
    # @param candidate [Hash] Candidate with :bid, :ask, :ltp
    # @return [Boolean] True if spread <= max_spread_pct
    def spread_ok?(candidate)
      bid = candidate[:bid]
      ask = candidate[:ask]
      ltp = candidate[:ltp]

      spread = calculate_spread(bid, ask, ltp)
      return false unless spread

      # IndexRules stores MAX_SPREAD_PCT as decimal (0.003 = 0.3%)
      # Our calculate_spread also returns decimal (0.04 = 4%)
      spread <= @rules.class::MAX_SPREAD_PCT
    end

    # Calculate spread as decimal (matches IndexRules formula)
    # @param bid [Float, nil] Bid price
    # @param ask [Float, nil] Ask price
    # @param _ltp [Float, nil] Last traded price (unused, kept for API compatibility)
    # @return [Float, nil] Spread as decimal (0.003 = 0.3%) or nil if cannot calculate
    def calculate_spread(bid, ask, _ltp)
      return nil unless bid && ask && bid.positive? && ask.positive?

      # Match IndexRules formula: (ask - bid) / ask
      ((ask - bid) / ask.to_f).round(6)
    end

    # Determine reason for validation failure
    # @param details [Hash] Validation details
    # @return [String] Reason string
    def determine_reason(details)
      return 'valid' if details[:valid]

      reasons = []
      reasons << 'premium_below_min' unless details[:premium_check]
      reasons << 'insufficient_liquidity' unless details[:liquidity_check]
      reasons << 'spread_too_wide' unless details[:spread_check]

      reasons.join(', ')
    end
  end
end

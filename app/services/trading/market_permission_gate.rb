# frozen_string_literal: true

module Trading
  # Hard gate: regime snapshot + chain signal must justify options buying.
  class MarketPermissionGate
    # keyword_init: required for keyword construction (RuboCop redundant warning is incorrect here)
    Result = Struct.new(:allowed, :reason, :code, keyword_init: true) # rubocop:disable Style/RedundantStructKeywordInit

    def initialize(snapshot:, chain_signal:, final_direction:, smc_decision: nil)
      @snapshot = snapshot
      @chain = chain_signal
      @direction = final_direction.to_sym
      @smc_decision = smc_decision
    end

    def call
      cfg = gate_config
      return pass if cfg[:enabled] != true

      unless trending_structure?
        return reject('Not in a directional trend structure', :not_trending)
      end

      min_conv = cfg[:min_conviction_score].to_i
      min_conv = 70 if min_conv.zero?
      if @snapshot.conviction_score < min_conv
        return reject("Conviction #{@snapshot.conviction_score} < #{min_conv}", :low_conviction)
      end

      unless strong_enough?
        return reject('Structure strength below threshold', :weak_strength)
      end

      if @snapshot.volatility_state == :exhausted_high
        return reject('Volatility exhausted / late spike', :exhausted_volatility)
      end

      unless participation_ok?
        return reject('Participation too low for OB', :low_participation)
      end

      min_chain = cfg[:min_chain_confidence].to_i
      min_chain = 40 if min_chain.zero?
      if @chain.direction_confidence < min_chain
        return reject("Chain confidence #{@chain.direction_confidence} < #{min_chain}", :low_chain_confidence)
      end

      unless @chain.oi_confirmation
        return reject('OI / flow does not confirm direction', :oi_not_confirmed)
      end

      if cfg[:require_premium_expansion] == true && !@chain.premium_expansion
        return reject('Premium expansion not detected', :no_premium_expansion)
      end

      if cfg[:require_smc_alignment] == true && smc_conflicts?
        return reject("SMC bias #{@smc_decision} conflicts with direction #{@direction}", :smc_misaligned)
      end

      pass
    end

    private

    def gate_config
      AlgoConfig.fetch.dig(:market_context, :gate) || {}
    rescue StandardError
      {}
    end

    def trending_structure?
      %i[bullish_trend bearish_trend].include?(@snapshot.structure)
    end

    def strong_enough?
      @snapshot.strength == :strong
    end

    def participation_ok?
      case @snapshot.participation
      when :high
        true
      when :normal
        gate_config[:allow_normal_participation] == true
      else
        false
      end
    end

    def smc_conflicts?
      return false if @smc_decision.nil? || @smc_decision == :no_trade

      ((@direction == :bullish) && (@smc_decision == :put)) ||
        ((@direction == :bearish) && (@smc_decision == :call))
    end

    def pass
      Result.new(allowed: true, reason: 'ok', code: :ok)
    end

    def reject(reason, code)
      Result.new(allowed: false, reason: reason, code: code)
    end
  end
end

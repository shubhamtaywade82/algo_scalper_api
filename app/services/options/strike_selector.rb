# frozen_string_literal: true

module Options
  # institutional strike-type classification based on momentum score.
  class StrikeSelector
    def self.strike_type_for_momentum(momentum_score)
      # score is 0-3 from MomentumValidator
      normalized = momentum_score.to_f / 3.0
      new(momentum: normalized).strike_type
    end

    def initialize(momentum: nil)
      @momentum = momentum
    end

    def strike_type
      return :skip if @momentum.nil?
      return :atm if @momentum > 0.60  # score >= 2/3: strong momentum → ATM+OTM allowed
      return :atm if @momentum > 0.25  # score >= 1/3: moderate momentum → ATM only (was :itm, now :atm)

      # score == 0: no momentum confirmation → skip
      :skip
    end
  end
end

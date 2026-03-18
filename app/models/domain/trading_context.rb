# frozen_string_literal: true

module Domain
  class TradingContext
    attr_reader :day_type, :session, :regime, :score, :stability

    def initialize(day_type:, session:, regime:, score:, stability: 0)
      @day_type = day_type
      @session = session
      @regime = regime
      @score = score
      @stability = stability
    end

    def tradable?
      return false if regime == :chop
      return false if score < min_score
      return false if stability < 3

      true
    end

    def min_score
      day_type == :expiry ? 60 : 50
    end
  end
end

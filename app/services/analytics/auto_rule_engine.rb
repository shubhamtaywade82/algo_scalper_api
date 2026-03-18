module Analytics
  class AutoRuleEngine
    def initialize(trades)
      @trades = trades
    end

    def call
      best = Analytics::BestSetupsExtractor.new(@trades).call
      threshold = Analytics::ThresholdOptimizer.new(@trades).call[:best_threshold]

      {
        rules: build_rules(best),
        position_sizing: build_position_sizing(best, threshold)
      }
    end

    private

    def build_rules(best)
      common = best[:common]

      {
        allowed_day_type: common[:day_type],
        allowed_session: common[:session],
        allowed_regime: common[:regime],
        min_score: common[:score_avg].to_i
      }
    end

    def build_position_sizing(best, threshold)
      base_score = threshold[:threshold]

      {
        high_confidence: {
          score: base_score + 10,
          multiplier: 1.5
        },
        medium_confidence: {
          score: base_score,
          multiplier: 1.0
        },
        low_confidence: {
          score: base_score - 10,
          multiplier: 0.5
        }
      }
    end
  end
end

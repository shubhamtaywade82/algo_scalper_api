# frozen_string_literal: true

module Research
  # Single source of truth for "percentage move of `value` relative to
  # `reference`" — shared by TradeScorer and PremiumLifecycleAnalyzer so the
  # formula (and its zero-guard) can't drift between the two independently.
  module PercentChange
    module_function

    def of(value, reference)
      return nil if reference.to_f.zero?

      ((value.to_f - reference.to_f) / reference.to_f * 100).round(4)
    end
  end
end

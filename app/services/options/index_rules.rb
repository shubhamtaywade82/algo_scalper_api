# frozen_string_literal: true

module Options
  # Index-specific trading rules (strike grid, liquidity, premium and spread floors).
  # One lookup for every caller, so each caller only decides what an unsupported index means
  # instead of carrying its own copy of the index-to-class mapping.
  module IndexRules
    RULES = { 'NIFTY' => 'Nifty', 'BANKNIFTY' => 'Banknifty', 'SENSEX' => 'Sensex' }.freeze

    # @param index_key [String, Symbol, nil] e.g. :NIFTY, "banknifty"
    # @return [Options::IndexRules::Base, nil] nil for an unsupported index
    def self.for(index_key)
      class_name = RULES[index_key.to_s.strip.upcase]
      const_get(class_name).new if class_name
    end
  end
end

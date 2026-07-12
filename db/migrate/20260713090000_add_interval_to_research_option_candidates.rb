# frozen_string_literal: true

# OptionCandidate#bars matches Research::OptionBar rows on
# (underlying_symbol, expiry_flag, option_type, strike_label) only — since
# research_option_bars is additionally keyed by `interval`, and strike_label
# is a relative ("ATM") rather than absolute identity, this column lets
# OptionCandidate#bars narrow to the exact interval a given candidate was
# fetched at instead of silently blending bars from a different timeframe.
class AddIntervalToResearchOptionCandidates < ActiveRecord::Migration[7.1]
  def change
    add_column :research_option_candidates, :interval, :string, null: false, default: "5"
  end
end

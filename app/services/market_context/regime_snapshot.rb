# frozen_string_literal: true

module MarketContext
  # Composed intraday context for options-buying permission and strategy selection.
  # Not a binary "options day" label — use conviction_score + fields for gating.
  RegimeSnapshot = Data.define(
    :structure,
    :strength,
    :volatility_state,
    :participation,
    :conviction_score,
    :displacement,
    :legacy_regime,
    :legacy_confidence,
    :raw
  )
end

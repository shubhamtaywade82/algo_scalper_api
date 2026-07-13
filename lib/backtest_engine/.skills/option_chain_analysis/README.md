# Option Chain Analysis Analyst Skill

This skill functions as a specialized quantitative options researcher. It maps the option chain landscape to expose participant positioning, walls, spreads, and Greek distributions before strategy entries.

## Option Intelligence Layer (OIL)

The Option Chain Analysis skill writes stateful, continuously updated data structures under `data/knowledge_base/` for down-stream consumption:

```text
data/knowledge_base/option_intelligence/
├── expiry_profile.json              # Expiry term structure, IV comparison
├── strike_quality_rankings.json     # Ranks of strikes based on the scoring model
├── liquidity_heatmap.json           # Spreads and depth matrices per strike
├── oi_heatmap.json                  # Net Open Interest, delta change, and buildups
├── iv_surface.json                  # Implied volatility skew and smile shapes
├── greeks_surface.json              # Delta, gamma, theta, vega allocations
└── gamma_exposure_map.json          # Dealer positioning and net Gamma profiles
```

### Downstream Queries
* **Strategy Generator** asks: *"Which strikes currently have institutional-quality liquidity?"* (Looks up `strike_quality_rankings.json`)
* **Strike Selector** asks: *"Which 0.45–0.55 delta contracts score above 85?"* (Looks up `strike_quality_rankings.json` filter)
* **Trade Management** asks: *"Has dealer gamma flipped or has the call wall migrated?"* (Looks up `gamma_exposure_map.json` or `oi_heatmap.json`)
* **Risk Manager** asks: *"Has liquidity deteriorated enough to avoid new entries?"* (Looks up `liquidity_heatmap.json`)

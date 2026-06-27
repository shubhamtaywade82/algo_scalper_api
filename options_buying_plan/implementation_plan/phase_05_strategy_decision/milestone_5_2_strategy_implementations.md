# Milestone 5.2: Strategy Implementations

**Phase:** 5 — Strategy & Decision Layer  
**Goal:** Multiple deterministic strategies as plugins.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement ORBStrategy (Opening Range Breakout)
- [ ] Create `app/strategies/orb_strategy.rb`
- [ ] Entry: Price breaks OR high/low (15m or 30m) with volume > 1.5x avg
- [ ] Filters:
  - Market Context: :allow_trading
  - Regime: trending or expanding (not compressing)
  - Structure: HH/HL for long, LH/LL for short
  - Momentum: accelerating in breakout direction
  - Liquidity: score > 60
  - Option Intelligence: IV rank < 60, theta risk < 50
- [ ] Exit:
  - Target: 1.5x OR range or 2:1 R:R
  - Stop: OR midpoint or 1 ATR
  - Time: exit by 14:30 if not hit
  - Trail: ATR trailing after 1R profit
- [ ] Parameters: `or_minutes` (15/30), `volume_multiplier`, `target_mult`, `stop_atr_mult`

### 2. Implement TrendFollowingStrategy
- [ ] Create `app/strategies/trend_following_strategy.rb`
- [ ] Entry: Pullback to EMA 21 in aligned trend (EMA 9 > 21 > 50)
- [ ] Filters:
  - Regime: trending_up/down (ADX > 25)
  - Structure: HL/HH (long) or LH/LL (short)
  - Momentum: ROC positive/negative aligned
  - VWAP: price on correct side of VWAP
  - Option: delta 0.4-0.6, IV rank < 50
- [ ] Exit:
  - Target: prior swing high/low or 2 ATR
  - Stop: EMA 21 or 1.5 ATR
  - Trail: EMA 9 then EMA 21
  - Structure break: CHOCH triggers exit
- [ ] Parameters: `ema_fast`, `ema_medium`, `ema_slow`, `adx_threshold`, `pullback_depth`

### 3. Implement PullbackStrategy
- [ ] Create `app/strategies/pullback_strategy.rb`
- [ ] Entry: Pullback to VWAP/EMA 9 in strong trend with structure support
- [ ] Filters:
  - Regime: trending (ADX > 20)
  - Structure: pullback to FVG or OB, not breaking HL/HH
  - Momentum: decelerating on pullback, accelerating on resume
  - Volume: lower on pullback, higher on resume
  - Liquidity: score > 70
- [ ] Exit:
  - Target: prior swing extreme + 0.5 ATR
  - Stop: pullback low/high or 1 ATR
  - Time: max 2 hours
- [ ] Parameters: `pullback_ema`, `max_pullback_atr`, `volume_ratio`

### 4. Implement LiquiditySweepStrategy
- [ ] Create `app/strategies/liquidity_sweep_strategy.rb`
- [ ] Entry: Liquidity sweep detected + reversal candle + structure alignment
- [ ] Filters:
  - Market Structure: sweep of equal highs/lows or session extreme
  - Momentum: sharp reversal (ROC spike opposite direction)
  - Volume: sweep candle volume > 2x average
  - Option Intelligence: gamma acceleration in reversal direction
  - Liquidity: score > 65 (need liquidity for entry)
- [ ] Exit:
  - Target: sweep origin + 1 ATR or prior structure level
  - Stop: beyond sweep extreme + 0.5 ATR
  - Trail: aggressive (0.5 ATR) after 0.5R
- [ ] Parameters: `sweep_lookback`, `reversal_candle_type`, `volume_mult`

### 5. Implement BreakoutStrategy
- [ ] Create `app/strategies/breakout_strategy.rb`
- [ ] Entry: Volume-confirmed break of consolidation range (BB squeeze + range)
- [ ] Filters:
  - Structure: range-bound (BB width < 20th percentile)
  - Momentum: ATR expanding, ROC accelerating
  - Volume: breakout candle volume > 2x 20-period avg
  - Regime: expanding volatility
  - Option: IV rank 30-70, positive gamma
- [ ] Exit:
  - Target: range height projected from breakout
  - Stop: back inside range (failed breakout)
  - Trail: ATR after 1R
- [ ] Parameters: `bb_period`, `bb_width_pct`, `volume_mult`, `range_lookback`

### 6. Implement ReversalStrategy
- [ ] Create `app/strategies/reversal_strategy.rb`
- [ ] Entry: Divergence + CHOCH + liquidity sweep at key level
- [ ] Filters:
  - Structure: CHOCH confirmed (break of HL/LH)
  - Momentum: RSI/MACD divergence (price HH, indicator LH)
  - Market Structure: sweep of key level (PDH/PDL, session extreme)
  - Volume: divergence candle volume spike
  - Option: IV falling (mean reversion), gamma supportive
- [ ] Exit:
  - Target: prior swing or 2:1 R:R
  - Stop: beyond reversal extreme
  - Time: max 90 minutes
- [ ] Parameters: `divergence_lookback`, `choch_confirmation`, `min_rr`

### 7. Add MomentumContinuationStrategy
- [ ] Create `app/strategies/momentum_continuation_strategy.rb`
- [ ] Entry: Strong momentum candle (marubozu) in trend direction after pullback
- [ ] Filters:
  - Regime: trending, expanding volatility
  - Momentum: ROC > 80th percentile, ATR expanding
  - Structure: no opposing structure nearby
  - Volume: momentum candle volume > 3x avg
  - Option: delta > 0.5, gamma accelerating
- [ ] Exit:
  - Target: 2-3 ATR or momentum exhaustion (RSI > 80)
  - Stop: 1 ATR behind momentum candle
  - Trail: 0.5 ATR aggressive
- [ ] Parameters: `momentum_threshold`, `volume_mult`, `rsi_exit`

### 8. Implement RangeExpansionStrategy
- [ ] Create `app/strategies/range_expansion_strategy.rb`
- [ ] Entry: NR7/NR4 candle (narrowest range 7/4 periods) followed by expansion
- [ ] Filters:
  - Structure: compression (BB squeeze, low ATR)
  - Volatility: ATR < 20th percentile
  - Momentum: expansion candle breaks NR range with volume
  - Regime: expanding from compression
  - Option: IV low (cheap vega), gamma positive
- [ ] Exit:
  - Target: 2x NR range or prior swing
  - Stop: opposite side of NR candle
  - Time: session end if not hit
- [ ] Parameters: `nr_period` (4/7), `expansion_mult`, `atr_pct_threshold`

### 9. Create Strategy Parameter Configuration
- [ ] Create `config/strategies.yml` with per-environment params:
  ```yaml
  development:
    orb:
      or_minutes: 15
      volume_multiplier: 1.5
    trend_following:
      adx_threshold: 20
  paper:
    orb:
      or_minutes: 30
      volume_multiplier: 1.3
  production:
    orb:
      or_minutes: 15
      volume_multiplier: 1.5
  ```
- [ ] Load in `AppConfig.strategies`
- [ ] Strategy receives params via `parameters` method

### 10. Add Strategy Performance Tracking
- [ ] Extend `LearningEngine` (Phase 8) to track per-strategy:
  - Win rate, expectancy, avg R:R, max drawdown
  - Performance by regime, time of day, expiry proximity
- [ ] Store in `learning_records` with `strategy_name`
- [ ] Dashboard endpoint for strategy comparison

### 11. Write Isolated Tests for Each Strategy
- [ ] Create `spec/strategies/`
- [ ] Fixtures: candle sequences triggering each strategy
- [ ] Test entry signals match manual analysis
- [ ] Test exit signals at targets/stops
- [ ] Test parameter sensitivity
- [ ] Test filter combinations (regime + structure + momentum)

### 12. Create Strategy Documentation
- [ ] Create `docs/strategies.md` with:
  - Entry rules (exact conditions)
  - Exit rules (all scenarios)
  - Parameters with defaults and ranges
  - Ideal market conditions
  - Known weaknesses
  - Backtest results summary

---

## Acceptance Criteria
- [ ] All 8 strategies implement BaseStrategy interface
- [ ] Each strategy passes isolated unit tests
- [ ] StrategyRegistry loads all 8 strategies
- [ ] Parameters configurable per environment
- [ ] StrategyValidator approves all strategies
- [ ] Performance tracking integrated with LearningEngine
- [ ] Documentation complete for all strategies

---

## Notes
- Strategies are DETERMINISTIC - same input always = same output
- No ML/randomness in strategies; AI Gateway validates only
- Strategies can be run in ensemble (Phase 5.4 scoring)
- Paper trading validates strategy behavior before live
- Each strategy should have > 100 trades in backtest before live
- Consider strategy correlation (don't run highly correlated strategies)
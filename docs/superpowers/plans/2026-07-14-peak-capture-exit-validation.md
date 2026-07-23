# Peak-Capture Exit Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 peak-capture exit simulators (mfe_retrace_25/35/50, gamma_state, velocity_ratchet) to the offline first-15m research pipeline, guard against synthetic-data contamination, extend the data window, and produce a 13-strategy retention-ratio comparison.

**Architecture:** All new exits plug into `Research::ExitCaptureAnalyzer`'s existing strategy registry (same method signature as the 8 existing sims). A single `STRATEGY_NAMES` constant replaces the three hardcoded exit-name lists. Data-source tagging + a strict-mode guard prevent the Black-Scholes premium simulator and synthetic underlying fallback from silently contaminating results. Underlying data window extends via `Instrument#intraday_ohlc` chunked backfill.

**Tech Stack:** Ruby 3.3 / Rails 8, RSpec, existing Research:: pipeline (V5), DhanHQ API via existing fetchers.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-14-peak-capture-exit-validation-design.md`
- Do NOT modify `Orders::MfeExitEngine`, `Orders::GammaTrailingEngine`, `Live::UnifiedExitChecker`, or any LOCKED live path (CLAUDE.md Stable-vs-Alpha policy). Research mirrors their math; it never calls them.
- `app/services/research/*` files are untracked work from a concurrent session — user approved editing them directly. Commit them as part of this work.
- Sim method contract (must match existing 8): `self.simulate_<name>(entry_price, entry_idx, active_candles, underlying_candles, breakout_type)` → `[exit_price (Float), exit_time (Time), exit_reason (String)]`. Sims that ignore the last two args use the `(entry_price, entry_idx, active_candles, *, **)` form like `simulate_trailing_stop_20`.
- All percentage-like config in decimal form (0.35 = 35%), matching repo convention.
- Never `git add -A` — another session has untracked files in this repo; stage files by exact path only.

---

### Task 1: Strategy registry + MFE-retrace exits

**Files:**
- Modify: `app/services/research/exit_capture_analyzer.rb` (registry at lines 23–32; new sims appended after `simulate_hold_to_close`)
- Modify: `app/services/research/research_report_generator.rb:99` (hardcoded `exit_names`)
- Modify: `app/services/research/statistical_validator.rb:13` (hardcoded `exit_names`)
- Test: `spec/services/research/exit_capture_analyzer_spec.rb` (create)

**Interfaces:**
- Produces: `Research::ExitCaptureAnalyzer::STRATEGY_NAMES` (Array<Symbol>, frozen) — the single source of truth all three files use; `simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio:)` plus three thin wrappers `simulate_mfe_retrace_25/35/50`.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing spec**

Create `spec/services/research/exit_capture_analyzer_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::ExitCaptureAnalyzer do
  # Synthetic 1-min premium candles. Shape A ("round trip", the 06-30/07-07b failure):
  # entry 100 -> peak 130 at minute 10 -> collapse to 20 by minute 30 -> flat to close.
  def round_trip_candles(base_time: Time.zone.parse("2026-07-10 09:30:00"))
    prices = []
    prices += (0..10).map { |i| 100.0 + (3.0 * i) }          # 100 -> 130 (peak at idx 10)
    prices += (1..20).map { |i| [130.0 - (5.5 * i), 20.0].max } # collapse to 20
    prices += Array.new(30, 20.0)                             # flat
    to_candles(prices, base_time)
  end

  # Shape B ("slow grind", the 07-13 shape): entry 100, +0.5/min for 120 min, then flat.
  def slow_grind_candles(base_time: Time.zone.parse("2026-07-10 09:30:00"))
    prices = (0..120).map { |i| 100.0 + (0.5 * i) } + Array.new(30, 160.0)
    to_candles(prices, base_time)
  end

  def to_candles(closes, base_time)
    closes.each_with_index.map do |c, i|
      { timestamp: base_time + i.minutes, open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1000 }
    end
  end

  describe "STRATEGY_NAMES" do
    it "includes the original 8 and the 5 new strategies" do
      expect(described_class::STRATEGY_NAMES).to include(
        :fixed_30, :fixed_50, :trail_20, :und_ema9, :prem_ema5,
        :momentum_decay, :hybrid_divergence, :hold_to_close,
        :mfe_retrace_25, :mfe_retrace_35, :mfe_retrace_50,
        :gamma_state, :velocity_ratchet
      )
    end
  end

  describe ".simulate_mfe_retrace_35" do
    it "exits at peak - 0.35*MFE on the round-trip series" do
      candles = round_trip_candles
      exit_price, _time, reason = described_class.simulate_mfe_retrace_35(100.0, 1, candles)
      # peak high = 130.5, MFE = 30.5, stop = 130.5 - 0.35*30.5 = 119.825
      expect(exit_price).to be_within(0.01).of(119.83)
      expect(reason).to eq("mfe_retrace")
    end

    it "does not exit prematurely on the slow grind (rides to close)" do
      candles = slow_grind_candles
      exit_price, _time, reason = described_class.simulate_mfe_retrace_35(100.0, 1, candles)
      # stop never hit while grinding up; flat tail never retraces 35% of a 60.5-pt MFE
      expect(reason).to eq("market_close")
      expect(exit_price).to be_within(0.01).of(160.0)
    end
  end
end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb`
Expected: FAIL — `uninitialized constant ... STRATEGY_NAMES` / `undefined method simulate_mfe_retrace_35`

- [ ] **Step 3: Implement registry + MFE-retrace sims**

In `exit_capture_analyzer.rb`, above `def self.run`:

```ruby
    STRATEGY_NAMES = %i[
      fixed_30 fixed_50 trail_20 und_ema9 prem_ema5
      momentum_decay hybrid_divergence hold_to_close
      mfe_retrace_25 mfe_retrace_35 mfe_retrace_50
      gamma_state velocity_ratchet
    ].freeze
```

Replace the `rules = { ... }` literal inside `run` with:

```ruby
      rules = STRATEGY_NAMES.index_with { |name| method(:"simulate_#{name}") }
```

Append after `simulate_hold_to_close`:

```ruby
    # 9-11. MFE retrace exits — mirror of live Orders::MfeExitEngine:
    # stop = peak - ratio * (peak - entry), active once MFE > 0.
    def self.simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio:)
      peak = entry_price
      active_candles[entry_idx..].each do |c|
        peak = [peak, c[:high]].max
        mfe = peak - entry_price
        next unless mfe.positive?

        stop = peak - (mfe * ratio)
        return [stop, c[:timestamp], "mfe_retrace"] if c[:low] <= stop
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    def self.simulate_mfe_retrace_25(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.25)
    end

    def self.simulate_mfe_retrace_35(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.35)
    end

    def self.simulate_mfe_retrace_50(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.50)
    end
```

Note: `run` will raise `NameError` for the not-yet-written `simulate_gamma_state`/`simulate_velocity_ratchet` if invoked now — that's fine; Tasks 2–3 add them, and this task's spec only calls the MFE sims directly.

In `research_report_generator.rb` line 99 replace:

```ruby
      exit_names = [:fixed_30, :fixed_50, :trail_20, :und_ema9, :prem_ema5, :momentum_decay, :hybrid_divergence, :hold_to_close]
```

with:

```ruby
      exit_names = Research::ExitCaptureAnalyzer::STRATEGY_NAMES
```

Same one-line replacement in `statistical_validator.rb` line 13.

- [ ] **Step 4: Run spec, verify the two MFE examples and STRATEGY_NAMES example pass**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/research/exit_capture_analyzer.rb app/services/research/research_report_generator.rb app/services/research/statistical_validator.rb spec/services/research/exit_capture_analyzer_spec.rb
git commit -m "research: add MFE-retrace exit sims + single strategy registry"
```

---

### Task 2: gamma_state exit sim

**Files:**
- Modify: `app/services/research/exit_capture_analyzer.rb` (append sim)
- Test: `spec/services/research/exit_capture_analyzer_spec.rb` (add describe block)

**Interfaces:**
- Produces: `simulate_gamma_state(entry_price, entry_idx, active_candles, *, **)` → standard triple.
- Consumes: `STRATEGY_NAMES` from Task 1 (name already listed).

- [ ] **Step 1: Write the failing spec** (add to existing spec file)

```ruby
  describe ".simulate_gamma_state" do
    it "exits via survival stop when the premium collapses before reaching +10%" do
      # entry 100, drifts down immediately -> survival stop at entry*0.88 = 88
      base = Time.zone.parse("2026-07-10 09:30:00")
      closes = (0..30).map { |i| 100.0 - (1.0 * i) }
      candles = closes.each_with_index.map do |c, i|
        { timestamp: base + i.minutes, open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1000 }
      end
      exit_price, _t, reason = described_class.simulate_gamma_state(100.0, 1, candles)
      expect(exit_price).to be_within(0.01).of(88.0)
      expect(reason).to eq("gamma_state_stop")
    end

    it "exits via exhaustion trail (peak*0.90) when velocity stalls after a rally" do
      candles = round_trip_candles
      exit_price, _t, reason = described_class.simulate_gamma_state(100.0, 1, candles)
      # Rally: velocity 3/close ≈ 2.4-3% < 5% threshold once above +10% profit,
      # so exhaustion trail peak*0.90 governs; peak high 130.5 -> stop 117.45
      expect(reason).to eq("gamma_state_stop")
      expect(exit_price).to be_within(1.0).of(117.45)
    end
  end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb -e simulate_gamma_state`
Expected: FAIL — `undefined method simulate_gamma_state`

- [ ] **Step 3: Implement** (append to analyzer; NIFTY constants mirrored verbatim from `Orders::GammaTrailingEngine::CONFIG[:nifty]`)

```ruby
    # 12. Gamma-state exit — mirror of live Orders::GammaTrailingEngine (NIFTY config).
    # 4 states from profit/velocity/acceleration; exit when candle low touches the state's stop.
    GAMMA_STATE_CFG = {
      gamma_trigger: 0.25, velocity_threshold: 0.05,
      gamma_trail: 0.65, normal_trail: 0.80, exhaust_trail: 0.90,
      survival_sl: 0.88, survival_profit: 0.10
    }.freeze

    def self.simulate_gamma_state(entry_price, entry_idx, active_candles, *, **)
      cfg = GAMMA_STATE_CFG
      peak = entry_price
      closes = active_candles.first(entry_idx).map { |c| c[:close] }

      active_candles[entry_idx..].each do |c|
        closes << c[:close]
        peak = [peak, c[:high]].max

        profit = (c[:close] - entry_price) / entry_price
        velocity = closes.size >= 2 ? (closes[-1] - closes[-2]) / closes[-2] : 0.0
        acceleration =
          if closes.size >= 3
            v1 = (closes[-2] - closes[-3]) / closes[-3]
            (velocity - v1)
          else
            0.0
          end

        stop =
          if profit < cfg[:survival_profit]
            entry_price * cfg[:survival_sl]
          elsif profit > cfg[:gamma_trigger] && acceleration.positive?
            peak * cfg[:gamma_trail]
          elsif velocity < cfg[:velocity_threshold]
            peak * cfg[:exhaust_trail]
          else
            peak * cfg[:normal_trail]
          end

        return [stop, c[:timestamp], "gamma_state_stop"] if c[:low] <= stop
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end
```

- [ ] **Step 4: Run full spec file, verify pass**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb`
Expected: PASS (5 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/research/exit_capture_analyzer.rb spec/services/research/exit_capture_analyzer_spec.rb
git commit -m "research: add gamma_state exit sim mirroring live GammaTrailingEngine"
```

---

### Task 3: velocity_ratchet exit sim

**Files:**
- Modify: `app/services/research/exit_capture_analyzer.rb` (append sim)
- Test: `spec/services/research/exit_capture_analyzer_spec.rb` (add describe block)

**Interfaces:**
- Produces: `simulate_velocity_ratchet(entry_price, entry_idx, active_candles, *, **)` → standard triple. Reasons: `"ratchet_floor"`, `"velocity_hard_exit"`, `"market_close"`.
- Consumes: `STRATEGY_NAMES` from Task 1.

Logic (from spec): arms at MFE ≥ 10% of entry. Floor = max(entry × 1.02, peak − gap); gap = MFE × (0.35 when 1-min velocity > 0, linearly down to 0.15 as velocity ≤ 0 — implemented as two bands: 0.35 while velocity positive, 0.15 once velocity non-positive). Floor never decreases (ratchet). Hard exit: close-to-close velocity negative 3 consecutive minutes AND close < EMA5 of closes.

- [ ] **Step 1: Write the failing spec** (add to spec file)

```ruby
  describe ".simulate_velocity_ratchet" do
    it "hard-exits within ~5 minutes of the peak on the round-trip series" do
      candles = round_trip_candles
      _price, exit_time, reason = described_class.simulate_velocity_ratchet(100.0, 1, candles)
      peak_time = candles[10][:timestamp] # idx 10 = the 130 peak
      expect(reason).to satisfy { |r| %w[ratchet_floor velocity_hard_exit].include?(r) }
      expect(exit_time - peak_time).to be <= 5.minutes
    end

    it "never realizes a loss once armed (floor >= entry*1.02)" do
      candles = round_trip_candles
      exit_price, _t, _r = described_class.simulate_velocity_ratchet(100.0, 1, candles)
      expect(exit_price).to be >= 102.0
    end

    it "rides the slow grind without premature exit" do
      candles = slow_grind_candles
      exit_price, _t, _reason = described_class.simulate_velocity_ratchet(100.0, 1, candles)
      # Grind peaks at 160.5; even the flat tail only triggers the tightened floor,
      # which by then ratcheted far above entry. Must capture most of the move.
      expect(exit_price).to be >= 145.0
    end
  end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb -e simulate_velocity_ratchet`
Expected: FAIL — `undefined method simulate_velocity_ratchet`

- [ ] **Step 3: Implement**

```ruby
    # 13. Velocity ratchet — peak-capture exit designed from V4/V5 findings:
    # premium peaked on every trade then gave back 28-99%; this floors the giveback.
    # Arms at MFE >= 10% of entry. Floor = max(entry*1.02, peak - gap);
    # gap = 35% of MFE while 1-min velocity > 0, tightens to 15% once velocity <= 0.
    # Floor only ever rises. Hard exit: velocity < 0 for 3 consecutive minutes AND close < EMA5.
    def self.simulate_velocity_ratchet(entry_price, entry_idx, active_candles, *, **)
      arm_threshold = entry_price * 1.10
      peak = entry_price
      floor = nil
      neg_velocity_run = 0
      closes = active_candles.first(entry_idx).map { |c| c[:close] }

      active_candles[entry_idx..].each do |c|
        closes << c[:close]
        peak = [peak, c[:high]].max

        velocity = closes.size >= 2 ? closes[-1] - closes[-2] : 0.0
        neg_velocity_run = velocity.negative? ? neg_velocity_run + 1 : 0

        if peak >= arm_threshold
          mfe = peak - entry_price
          gap_ratio = velocity.positive? ? 0.35 : 0.15
          candidate = [entry_price * 1.02, peak - (mfe * gap_ratio)].max
          floor = floor.nil? ? candidate : [floor, candidate].max
        end

        if floor
          return [floor, c[:timestamp], "ratchet_floor"] if c[:low] <= floor

          if neg_velocity_run >= 3 && closes.size >= 5
            ema5 = closes.last(5).sum / 5.0
            return [c[:close], c[:timestamp], "velocity_hard_exit"] if c[:close] < ema5
          end
        end
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end
```

- [ ] **Step 4: Run full spec file, verify pass**

Run: `bundle exec rspec spec/services/research/exit_capture_analyzer_spec.rb`
Expected: PASS (8 examples)

- [ ] **Step 5: Run rubocop on touched files, fix any offenses**

Run: `bundle exec rubocop app/services/research/exit_capture_analyzer.rb spec/services/research/exit_capture_analyzer_spec.rb`
Expected: no offenses (autocorrect layout-only ones with `-A` if any appear)

- [ ] **Step 6: Commit**

```bash
git add app/services/research/exit_capture_analyzer.rb spec/services/research/exit_capture_analyzer_spec.rb
git commit -m "research: add velocity_ratchet peak-capture exit sim"
```

---

### Task 4: Synthetic-fallback guard + option-source tagging

**Files:**
- Modify: `app/services/research/market_data_fetcher.rb` (lines ~46–51 synthetic-underlying fallback; `load_or_simulate_options` return path; `simulate_option_premium` call site at line ~185)
- Modify: `app/services/research/first_15m_engine.rb` (skip-and-count simulated-premium days)
- Test: `spec/services/research/market_data_fetcher_guard_spec.rb` (create)

**Interfaces:**
- Produces: `Research::MarketDataFetcher::SyntheticDataError` (StandardError subclass); `.run(..., strict: true)` kwarg (default true) — raises `SyntheticDataError` instead of generating a synthetic underlying dataset; `load_or_simulate_options(..., strict: true)` returns `[]` instead of Black-Scholes-simulated premiums, logging one warn per skipped day.
- Consumes: nothing new.

Rationale: the V4 run's constant gap/ATR/body-ratio columns almost certainly came from these silent fallbacks. Under strict mode, no simulated data can reach the results; skipped days are counted so the report can state "N of M days simulated".

- [ ] **Step 1: Write the failing spec**

Create `spec/services/research/market_data_fetcher_guard_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::MarketDataFetcher do
  describe "strict mode" do
    it "raises SyntheticDataError instead of generating a synthetic underlying dataset" do
      allow(Candles::Record).to receive(:where).and_return(Candles::Record.none)
      allow(File).to receive(:exist?).with("today_market_data.json").and_return(false)

      expect do
        described_class.run(symbol: "NO_SUCH_SYMBOL", lookback_days: 5, strict: true)
      end.to raise_error(Research::MarketDataFetcher::SyntheticDataError)
    end

    it "returns [] from load_or_simulate_options instead of simulating premiums" do
      nifty_candles = [{ timestamp: Time.zone.now, open: 25_000.0, high: 25_010.0,
                         low: 24_990.0, close: 25_005.0, volume: 100 }]
      allow(Research::OptionBar).to receive(:where).and_return(Research::OptionBar.none)
      allow(Research::OptionCandleFetcher).to receive(:call).and_return([])

      result = described_class.load_or_simulate_options(
        "NIFTY", "CE", 25_000, Time.zone.today, nifty_candles, strike_label: "ATM", strict: true
      )
      expect(result).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/research/market_data_fetcher_guard_spec.rb`
Expected: FAIL — unknown keyword `strict` / uninitialized constant `SyntheticDataError`

- [ ] **Step 3: Implement guard**

In `market_data_fetcher.rb`:

```ruby
  class MarketDataFetcher
    class SyntheticDataError < StandardError; end
```

Change `def self.run(symbol: "NIFTY", lookback_days: 90, interval: "1")` to
`def self.run(symbol: "NIFTY", lookback_days: 90, interval: "1", strict: true)`.

Replace the synthetic-underlying block (the `if all_dates.empty?` branch) with:

```ruby
      if all_dates.empty?
        if strict
          raise SyntheticDataError,
                "No historical #{symbol} data found; refusing to generate a synthetic dataset (strict mode)."
        end

        Rails.logger.warn("[Research::MarketDataFetcher] No historical #{symbol} data found, generating synthetic dataset.")
        all_dates = (0...lookback_days).map { |i| Time.zone.today - i.days }.reject { |d| d.saturday? || d.sunday? }.reverse
      end
```

Change `def self.load_or_simulate_options(symbol, option_type, strike, date, nifty_candles, strike_label: "ATM")` to add `strict: true`, and replace the final fallback line:

```ruby
      # Fallback: simulate option premium — forbidden in strict mode.
      if strict
        Rails.logger.warn("[Research::MarketDataFetcher] No real option bars for #{symbol} #{strike_label} #{option_type} on #{date}; day skipped (strict mode).")
        return []
      end

      simulate_option_premium(option_type, strike, nifty_candles)
```

Pass `strict: true` explicitly at the `load_or_simulate_options` call sites inside `run` (lines ~64–65) and in `first_15m_engine.rb:83`. In `first_15m_engine.rb`, the existing `next if option_candles.empty?` (line 92) already skips the day; add a counter so the report can state coverage — inside `run`, before the day loop: `skipped_days = 0`; increment where the ATM strike is missing (the existing `next unless opp[:strikes].key?("ATM")` path), and log the total after the loop:

```ruby
      Rails.logger.info("[Research::First15mEngine] Simulated #{days_data.size - skipped_days} of #{days_data.size} days (#{skipped_days} skipped: no real option data).")
```

- [ ] **Step 4: Run spec, verify pass**

Run: `bundle exec rspec spec/services/research/market_data_fetcher_guard_spec.rb spec/services/research/exit_capture_analyzer_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/research/market_data_fetcher.rb app/services/research/first_15m_engine.rb spec/services/research/market_data_fetcher_guard_spec.rb
git commit -m "research: strict mode - refuse synthetic underlying/premium data, count skipped days"
```

---

### Task 5: Underlying data-window extension

**Files:**
- Create: `app/services/research/underlying_backfill.rb`
- Test: `spec/services/research/underlying_backfill_spec.rb` (create)

**Interfaces:**
- Produces: `Research::UnderlyingBackfill.call(symbol: "NIFTY", lookback_days: 90)` → Integer (days now available). Fetches missing 1-min underlying days via the NIFTY index `Instrument#intraday_ohlc` in ≤75-day chunks and persists them as `Candles::Record` rows (`instrument_key: symbol, timeframe: "1m"`) so `MarketDataFetcher.run`'s existing DB read picks them up unchanged.
- Consumes: `Instrument#intraday_ohlc(interval:, from_date:, to_date:)` (existing, returns hash of parallel arrays: `open/high/low/close/volume/timestamp`), `Candles::Record` (existing model).

Option-side note: no new option backfill needed — `load_or_simulate_options` already tries `Research::OptionCandleFetcher` (Dhan ExpiredOptionsData) per day before giving up, and Task 4 makes the give-up explicit. Days where Dhan has no expired-option bars are skipped and counted.

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::UnderlyingBackfill do
  it "persists fetched OHLC arrays as 1m Candles::Record rows for missing days" do
    instrument = create(:instrument, :nifty_index)
    allow(Instrument).to receive(:find_by).and_return(instrument)

    t0 = Time.zone.parse("2026-07-06 09:15:00").to_i
    raw = {
      open: [100.0, 101.0], high: [101.0, 102.0], low: [99.0, 100.0],
      close: [101.0, 101.5], volume: [10, 12], timestamp: [t0, t0 + 60]
    }
    allow(instrument).to receive(:intraday_ohlc).and_return(raw)

    expect do
      described_class.call(symbol: "NIFTY", lookback_days: 5)
    end.to change { Candles::Record.where(instrument_key: "NIFTY", timeframe: "1m").count }.by(2)
  end

  it "returns the count of distinct days available after backfill" do
    instrument = create(:instrument, :nifty_index)
    allow(Instrument).to receive(:find_by).and_return(instrument)
    allow(instrument).to receive(:intraday_ohlc).and_return({})

    expect(described_class.call(symbol: "NIFTY", lookback_days: 5)).to be_a(Integer)
  end
end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/research/underlying_backfill_spec.rb`
Expected: FAIL — `uninitialized constant Research::UnderlyingBackfill`

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module Research
  # Backfills 1-min underlying candles into Candles::Record so
  # MarketDataFetcher's existing DB read covers more trading days.
  class UnderlyingBackfill
    CHUNK_DAYS = 75

    def self.call(symbol: "NIFTY", lookback_days: 90)
      instrument = Instrument.find_by(exchange: "nse", segment: "index", symbol_name: symbol)
      return existing_day_count(symbol) unless instrument

      existing = Candles::Record.where(instrument_key: symbol, timeframe: "1m")
                                .pluck(Arel.sql("DISTINCT ts::date")).to_set

      from = lookback_days.days.ago.to_date
      to = Time.zone.today

      (from..to).each_slice(CHUNK_DAYS) do |chunk|
        chunk_from = chunk.first
        chunk_to = chunk.last
        next if (chunk_from..chunk_to).all? { |d| existing.include?(d) || d.saturday? || d.sunday? }

        raw = instrument.intraday_ohlc(interval: "1", from_date: chunk_from.to_s, to_date: chunk_to.to_s)
        persist(symbol, raw, existing)
      rescue StandardError => e
        Rails.logger.warn("[Research::UnderlyingBackfill] chunk #{chunk_from}..#{chunk_to} failed: #{e.class} - #{e.message}")
      end

      existing_day_count(symbol)
    end

    def self.persist(symbol, raw, existing)
      return if raw.blank? || raw[:timestamp].blank?

      rows = raw[:timestamp].each_index.filter_map do |i|
        ts = Time.zone.at(raw[:timestamp][i])
        next if existing.include?(ts.to_date)

        {
          instrument_key: symbol, timeframe: "1m", ts: ts,
          open: raw[:open][i], high: raw[:high][i], low: raw[:low][i],
          close: raw[:close][i], volume: raw[:volume][i],
          created_at: Time.current, updated_at: Time.current
        }
      end
      Candles::Record.insert_all(rows) if rows.any?
    end

    def self.existing_day_count(symbol)
      Candles::Record.where(instrument_key: symbol, timeframe: "1m")
                     .pluck(Arel.sql("DISTINCT ts::date")).size
    end
  end
end
```

Note for the implementer: check `Candles::Record` column names before finalizing `persist` (`bin/rails runner 'puts Candles::Record.column_names.inspect'`) — if the model uses different column names (e.g. `symbol` instead of `instrument_key`), match whatever `MarketDataFetcher.run` line 15 queries by, since that is the read path this must feed.

- [ ] **Step 4: Run spec, verify pass**

Run: `bundle exec rspec spec/services/research/underlying_backfill_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/research/underlying_backfill.rb spec/services/research/underlying_backfill_spec.rb
git commit -m "research: chunked 1m underlying backfill to extend research window"
```

---

### Task 6: Full run + report regeneration

**Files:**
- Modify: `docs/research/first_15m_breakout_research.md` (append V5 peak-capture matrix section)
- Output: regenerated `data/research/*.json` / `*.csv`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Backfill the window**

Run: `bin/rails runner 'puts Research::UnderlyingBackfill.call(symbol: "NIFTY", lookback_days: 90)'`
Expected: prints day count (int). If it stays ~10, Dhan's intraday lookback is the binding constraint — record the actual number, do not fake it.

- [ ] **Step 2: Run the research engine in strict mode**

Run: `bin/rails runner 'Research::First15mEngine.run(symbol: "NIFTY", lookback_days: 90)'`
Expected: completes; log line `Simulated N of M days`; **abort and investigate if `SyntheticDataError` is raised** — that means the underlying window didn't extend.

- [ ] **Step 3: Sanity-check the new strategies appear**

Run: `python3 -c "import json; d=json.load(open('data/research/research_report_v4.json')); print(sorted(d['summary']['exit_performance_atm'].keys()))"`
Expected: 13 strategy keys including `mfe_retrace_35`, `gamma_state`, `velocity_ratchet`.

- [ ] **Step 4: Verify no simulated data leaked**

Run: `grep -c "day skipped (strict mode)" log/development.log | tail -1` (or check run output)
Expected: skips are logged, and `Simulated N of M` matches (M − skips). Spot-check 2 trades' gap/body-ratio values in the JSON — they must no longer be constant across all rows.

- [ ] **Step 5: Append results section to the research doc**

Add to `docs/research/first_15m_breakout_research.md` a `## 7. Peak-Capture Exit Validation (V5)` section containing: the 13-strategy matrix (win rate / avg return / retention ratio / capture efficiency / Sharpe / PF / CI), the N-of-M coverage line, and the verdict per the spec rule — a strategy wins only if OOS retention ratio beats the best existing exit AND the bootstrap 95% CI lower bound on return is above 0%; otherwise state "no validated edge" explicitly. Write the actual numbers from the run — no placeholders.

- [ ] **Step 6: Full research spec suite green**

Run: `bundle exec rspec spec/services/research/`
Expected: PASS (pre-existing failures in other dirs are out of scope)

- [ ] **Step 7: Commit**

```bash
git add docs/research/first_15m_breakout_research.md data/research/
git commit -m "research: peak-capture exit validation run - 13-strategy matrix + verdict"
```

---

## Verification (end-to-end)

1. `bundle exec rspec spec/services/research/` — all green.
2. `bin/rails zeitwerk:check` — clean (ignore the pre-existing DhanHQ EdisContract gem warning).
3. Report JSON contains 13 exit strategies; per-trade feature columns are no longer constant; coverage line present.
4. The doc's verdict follows the spec rule mechanically — no strategy is declared a winner without OOS + CI support.

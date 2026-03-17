# Options Profit Optimization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize options buying profitability by fixing a structure invalidation bug, tightening SL/TP/trailing for options, adding session-aware entry filtering, and controlling trade frequency.

**Architecture:** Fix sub-second structure invalidation config bypass, redesign it with options-aware dual condition (underlying move + premium drop), tighten existing exit thresholds via config, add adaptive trailing drawdown to institutional trailing, add session override logic to EntryQualityFilter, change cooldown from per-symbol to per-index, and add a max concurrent positions guard.

**Tech Stack:** Ruby 3.3.4, Rails 8.0.2, RSpec, Redis (cache), PostgreSQL

**Spec:** `docs/superpowers/specs/2026-03-16-options-profit-optimization-design.md`

---

## Chunk 1: Structure Invalidation Bug Fix & Redesign

### Task 1: Fix structure invalidation config bypass in sub-second path

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb:86-96`
- Test: `spec/services/live/unified_exit_checker_spec.rb`

The sub-second structure invalidation check (lines 86-96) never checks `risk.exits.structure_invalidation.enabled`. The 5-second path in `exit_enforcement.rb:372` correctly checks via `structure_invalidation_enabled?`. We need to add the same check to the sub-second path.

- [ ] **Step 1: Write the failing test**

```ruby
# In spec/services/live/unified_exit_checker_spec.rb
# Add to the structure invalidation context

describe 'structure invalidation config check' do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      meta: {
        'structure_invalidation_price' => 23500.0,
        'index_key' => 'NIFTY',
        'direction' => 'long_ce'
      },
      created_at: 5.minutes.ago
    )
  end

  before do
    # CRITICAL: Clear the TTL-cached exit_config to ensure AlgoConfig mocks take effect
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)

    allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
      pnl: -500, pnl_pct: -0.03, ltp: 150.0, hwm_pnl: 0
    })
    # Structure would be invalidated (underlying broke below level)
    allow(described_class).to receive(:resolve_underlying_ltp).and_return(23400.0)
    # Stub all other exit checks to isolate structure invalidation testing
    allow(described_class).to receive(:early_exit_triggered?).and_return(false)
    allow(described_class).to receive(:loss_limit_hit?).and_return(false)
    allow(described_class).to receive(:emergency_peak_loss_exit_triggered?).and_return(false)
    allow(described_class).to receive(:profit_target_hit?).and_return(false)
    allow(described_class).to receive(:premium_momentum_failure_hit?).and_return(false)
    allow(described_class).to receive(:trailing_stop_hit?).and_return(false)
    allow(described_class).to receive(:time_based_exit?).and_return(false)
  end

  context 'when structure_invalidation.enabled is false' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          exits: {
            structure_invalidation: {
              enabled: false,
              min_hold_seconds: 120,
              buffer_pct: 0.004
            }
          }
        }
      })
    end

    it 'skips structure invalidation check entirely' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to be_nil
    end
  end

  context 'when structure_invalidation.enabled is true' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          exits: {
            structure_invalidation: {
              enabled: true,
              min_hold_seconds: 120,
              buffer_pct: 0.004
            }
          }
        }
      })
    end

    it 'checks structure invalidation and exits when invalidated' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to include(exit: true)
      expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'structure invalidation config check' -v`
Expected: FAIL — the `enabled: false` test fails because the sub-second path doesn't check config.

- [ ] **Step 3: Implement the fix**

In `app/services/live/unified_exit_checker.rb`, replace lines 86-96:

```ruby
        # 6. Structure Invalidation (underlying broke past entry structure level)
        # Skip until min hold time to avoid tick-noise exits and reduce brokerage from instant flips.
        if structure_invalidation_enabled? &&
           (invalidation_price = tracker.meta&.dig('structure_invalidation_price')) &&
           structure_min_hold_elapsed?(tracker)
          underlying_ltp = resolve_underlying_ltp(tracker.meta&.dig('index_key'))
          if underlying_ltp && structure_invalidated?(tracker, underlying_ltp, invalidation_price)
            return {
              exit: true,
              reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} broke #{invalidation_price})"
            }
          end
        end
```

Add the private method (reuse the same logic from `risk_manager_service/config.rb`):

```ruby
      def structure_invalidation_enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        cfg.fetch(:enabled, true)
      rescue StandardError
        true
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'structure invalidation config check' -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/live/unified_exit_checker.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "fix: add config check to sub-second structure invalidation path

The sub-second structure invalidation check in unified_exit_checker.rb
never checked risk.exits.structure_invalidation.enabled, causing exits
to fire even when disabled. Now matches the 5-second interval path."
```

---

### Task 2: Implement options-aware dual condition for structure invalidation

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb:86-96` (the code just fixed in Task 1)
- Modify: `app/services/entries/entry_guard.rb:918` (store initial peak_premium)
- Test: `spec/services/live/unified_exit_checker_spec.rb`

Replace the single underlying-price check with dual condition: underlying moved 1%+ against direction AND premium dropped 5%+ from peak.

- [ ] **Step 1: Write failing tests for dual condition**

```ruby
# In spec/services/live/unified_exit_checker_spec.rb
describe 'options-aware structure invalidation dual condition' do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      meta: {
        'structure_invalidation_price' => 23500.0,
        'index_key' => 'NIFTY',
        'direction' => 'long_ce',
        'entry_underlying_price' => 23500.0,
        'peak_premium' => 200.0
      },
      created_at: 5.minutes.ago,
      entry_price: 180.0
    )
  end

  before do
    # CRITICAL: Clear the TTL-cached exit_config to ensure AlgoConfig mocks take effect
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)

    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        exits: {
          structure_invalidation: {
            enabled: true,
            min_hold_seconds: 120,
            buffer_pct: 0.004,
            underlying_move_pct: 0.01,
            premium_drop_pct: 0.05
          }
        }
      }
    })
    # Make other exit checks return false
    allow(described_class).to receive(:early_exit_triggered?).and_return(false)
    allow(described_class).to receive(:loss_limit_hit?).and_return(false)
    allow(described_class).to receive(:emergency_peak_loss_exit_triggered?).and_return(false)
    allow(described_class).to receive(:profit_target_hit?).and_return(false)
    allow(described_class).to receive(:premium_momentum_failure_hit?).and_return(false)
    allow(described_class).to receive(:trailing_stop_hit?).and_return(false)
    allow(described_class).to receive(:time_based_exit?).and_return(false)
  end

  context 'when only underlying moved 1%+ (premium still near peak)' do
    before do
      # Underlying dropped 1.5% from 23500 to 23147
      allow(described_class).to receive(:resolve_underlying_ltp).and_return(23147.0)
      # Premium dropped only 2% from peak (200 → 196)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
        pnl: -200, pnl_pct: -0.02, ltp: 196.0, hwm_pnl: 0
      })
    end

    it 'does NOT trigger structure invalidation' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to be_nil
    end
  end

  context 'when only premium dropped 5%+ (underlying stable)' do
    before do
      # Underlying barely moved (0.2%)
      allow(described_class).to receive(:resolve_underlying_ltp).and_return(23453.0)
      # Premium dropped 10% from peak (200 → 180)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
        pnl: -1000, pnl_pct: -0.10, ltp: 180.0, hwm_pnl: 0
      })
    end

    it 'does NOT trigger structure invalidation' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to be_nil
    end
  end

  context 'when BOTH underlying moved 1%+ AND premium dropped 5%+' do
    before do
      # Underlying dropped 1.5% from 23500 to 23147
      allow(described_class).to receive(:resolve_underlying_ltp).and_return(23147.0)
      # Premium dropped 15% from peak (200 → 170)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
        pnl: -1500, pnl_pct: -0.15, ltp: 170.0, hwm_pnl: 0
      })
    end

    it 'triggers structure invalidation' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to include(exit: true)
      expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
    end
  end

  context 'when dual condition config is absent (backward compat)' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          exits: {
            structure_invalidation: {
              enabled: true,
              min_hold_seconds: 120,
              buffer_pct: 0.004
              # No underlying_move_pct or premium_drop_pct
            }
          }
        }
      })
      # Underlying broke structure level (old behavior)
      allow(described_class).to receive(:resolve_underlying_ltp).and_return(23400.0)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
        pnl: -500, pnl_pct: -0.03, ltp: 150.0, hwm_pnl: 0
      })
    end

    it 'falls back to legacy single-condition check' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to include(exit: true)
      expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'options-aware structure invalidation' -v`
Expected: FAIL

- [ ] **Step 3: Implement the dual condition**

In `app/services/live/unified_exit_checker.rb`, replace the structure invalidation block (lines 86-96 area, already modified in Task 1):

```ruby
        # 6. Structure Invalidation (options-aware dual condition)
        if structure_invalidation_enabled? &&
           (invalidation_price = tracker.meta&.dig('structure_invalidation_price')) &&
           structure_min_hold_elapsed?(tracker)
          underlying_ltp = resolve_underlying_ltp(tracker.meta&.dig('index_key'))
          if underlying_ltp
            si_cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}

            if si_cfg[:underlying_move_pct] && si_cfg[:premium_drop_pct]
              # Options-aware dual condition
              if options_structure_invalidated?(tracker, underlying_ltp, snapshot, si_cfg)
                return {
                  exit: true,
                  reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} moved against entry, premium dropped from peak)"
                }
              end
            elsif structure_invalidated?(tracker, underlying_ltp, invalidation_price)
              # Legacy single condition (backward compat)
              return {
                exit: true,
                reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} broke #{invalidation_price})"
              }
            end
          end
        end
```

Add the private method:

```ruby
      def options_structure_invalidated?(tracker, underlying_ltp, snapshot, si_cfg)
        entry_underlying = tracker.meta&.dig('entry_underlying_price').to_f
        return false unless entry_underlying.positive?

        direction = tracker.meta&.dig('direction').to_s
        underlying_move_pct = si_cfg[:underlying_move_pct].to_f  # e.g. 0.01 for 1%

        # Condition A: underlying moved against direction by threshold %
        underlying_moved = case direction
                           when 'long_ce'
                             (entry_underlying - underlying_ltp) / entry_underlying >= underlying_move_pct
                           when 'long_pe'
                             (underlying_ltp - entry_underlying) / entry_underlying >= underlying_move_pct
                           else
                             false
                           end
        return false unless underlying_moved

        # Condition B: premium dropped from peak by threshold %
        peak_premium = tracker.meta&.dig('peak_premium').to_f
        return false unless peak_premium.positive?

        current_premium = snapshot[:ltp].to_f
        return false unless current_premium.positive?

        premium_drop_pct = si_cfg[:premium_drop_pct].to_f  # e.g. 0.05 for 5%
        premium_drop = (peak_premium - current_premium) / peak_premium
        premium_drop >= premium_drop_pct
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'options-aware structure invalidation' -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/live/unified_exit_checker.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: options-aware dual condition for structure invalidation

Replace single underlying-price check with dual condition:
1) Underlying moved 1%+ against trade direction from entry
2) Premium dropped 5%+ from peak
Both must be true. Falls back to legacy check when config absent."
```

---

### Task 3: Seed peak_premium in entry_guard and update config

**Files:**
- Modify: `app/services/entries/entry_guard.rb:918` (near meta_hash[:entry_premium])
- Modify: `config/algo.yml:224-227` (structure_invalidation section)
- Test: `spec/services/entries/entry_guard_spec.rb`

- [ ] **Step 1: Write the failing test**

**Important:** Read the existing `spec/services/entries/entry_guard_spec.rb` to find a context that exercises the meta_hash creation during entry (look for tests that check `meta_hash[:entry_premium]` or `apply_bos_metadata!`). Add the assertion in that same context. Example:

```ruby
# In the existing context that tests entry metadata creation:
it 'stores peak_premium in tracker meta at entry time' do
  # ... existing setup that triggers an entry ...
  expect(tracker.meta['peak_premium']).to eq(entry_price.to_f)
  expect(tracker.meta['peak_premium_at']).to be_present
end
```

If no suitable existing context exists, create a focused test that calls the private method `apply_bos_metadata!` or the entry path that populates `meta_hash` and verifies the new keys are present.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entries/entry_guard_spec.rb -t 'peak_premium' -v`
Expected: FAIL — peak_premium not set

- [ ] **Step 3: Add peak_premium to meta_hash in entry_guard.rb**

In `app/services/entries/entry_guard.rb`, after line 918 (`meta_hash[:entry_premium] = entry_price.to_f`), add:

```ruby
        meta_hash[:peak_premium] = entry_price.to_f
        meta_hash[:peak_premium_at] = Time.current.iso8601
```

- [ ] **Step 4: Update config/algo.yml structure_invalidation section**

Replace lines 222-227:

```yaml
  # Exit-layer overrides. Price-based structure invalidation uses options-aware dual condition.
  exits:
    structure_invalidation:
      enabled: true           # Re-enabled with options-aware dual condition
      min_hold_seconds: 120   # No structure exit until position age >= this (reduces churn)
      buffer_pct: 0.004       # Legacy: require underlying to breach level by this fraction
      underlying_move_pct: 0.01  # Underlying must move 1%+ against trade direction
      premium_drop_pct: 0.05    # Premium must drop 5%+ from peak
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/entries/entry_guard_spec.rb -t 'peak_premium' -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/entries/entry_guard.rb config/algo.yml spec/services/entries/entry_guard_spec.rb
git commit -m "feat: seed peak_premium at entry, enable dual structure invalidation

Set peak_premium in tracker meta at entry time so the options-aware
dual condition has data immediately. Re-enable structure invalidation
with underlying_move_pct: 0.01 and premium_drop_pct: 0.05."
```

---

### Task 4: Align 5-second structure invalidation path with dual condition

**Files:**
- Modify: `app/services/live/risk_manager_service/exit_enforcement.rb:379-404`
- Test: `spec/services/live/risk_manager_service_spec.rb`

The 5-second interval path uses `Risk::Rules::StructureInvalidationRule`. It should also support the dual condition. However, the rule engine pattern is different — the simplest approach is to add the dual condition check before delegating to the rule.

- [ ] **Step 1: Write the failing test**

```ruby
# In spec for exit_enforcement (find existing spec or create)
describe 'enforce_structure_invalidation_for with dual condition' do
  it 'skips exit when underlying moved but premium did not drop' do
    # Setup tracker with entry_underlying_price and peak_premium in meta
    # Mock underlying to show 1.5% move against direction
    # Mock premium to show only 2% drop (below 5% threshold)
    # Assert: no exit dispatched
  end

  it 'triggers exit when both underlying and premium conditions met' do
    # Setup tracker with entry_underlying_price and peak_premium in meta
    # Mock underlying to show 1.5% move against direction
    # Mock premium to show 8% drop from peak
    # Assert: exit dispatched with STRUCTURE_INVALIDATION reason
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/risk_manager_service_spec.rb -t 'dual condition' -v`
Expected: FAIL

- [ ] **Step 3: Add dual condition pre-check to enforce_structure_invalidation_for**

In `app/services/live/risk_manager_service/exit_enforcement.rb`, modify `enforce_structure_invalidation_for` (lines 379-404):

```ruby
      def enforce_structure_invalidation_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        si_cfg = (risk_config[:exits] || {})[:structure_invalidation] || {}

        # If options-aware dual condition is configured, check both conditions
        if si_cfg[:underlying_move_pct] && si_cfg[:premium_drop_pct]
          return unless options_structure_invalidated_enforcement?(tracker, snapshot, si_cfg)

          reason = 'STRUCTURE_INVALIDATION (dual: underlying move + premium drop)'
          exit_path = 'structure_invalidation'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          return
        end

        # Legacy: delegate to StructureInvalidationRule
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )

        rule = Risk::Rules::StructureInvalidationRule.new(config: { enabled: true })
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'STRUCTURE_INVALIDATION'
          exit_path = 'structure_invalidation'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_structure_invalidation_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def options_structure_invalidated_enforcement?(tracker, snapshot, si_cfg)
        # Check min hold time
        return false unless tracker.created_at && (Time.current - tracker.created_at) >= (si_cfg[:min_hold_seconds] || 120).to_i

        entry_underlying = tracker.meta&.dig('entry_underlying_price').to_f
        return false unless entry_underlying.positive?

        # Resolve current underlying (uses Live::UnderlyingLtpResolver included above)
        index_key = tracker.meta&.dig('index_key')
        underlying_ltp = resolve_underlying_ltp(index_key)
        return false unless underlying_ltp

        direction = tracker.meta&.dig('direction').to_s

        # Condition A: underlying moved against direction
        underlying_moved = case direction
                           when 'long_ce'
                             (entry_underlying - underlying_ltp) / entry_underlying >= si_cfg[:underlying_move_pct].to_f
                           when 'long_pe'
                             (underlying_ltp - entry_underlying) / entry_underlying >= si_cfg[:underlying_move_pct].to_f
                           else
                             false
                           end
        return false unless underlying_moved

        # Condition B: premium dropped from peak
        peak_premium = tracker.meta&.dig('peak_premium').to_f
        return false unless peak_premium.positive?

        current_premium = snapshot[:ltp].to_f
        return false unless current_premium.positive?

        premium_drop = (peak_premium - current_premium) / peak_premium
        premium_drop >= si_cfg[:premium_drop_pct].to_f
      end
```

**Important:** The `ExitEnforcement` module does NOT include `Live::UnderlyingLtpResolver`. You must add it. At the top of `app/services/live/risk_manager_service/exit_enforcement.rb`, inside the module body, add:

```ruby
      include Live::UnderlyingLtpResolver
```

This provides `resolve_underlying_ltp(index_key)` used in the method above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/risk_manager_service_spec.rb -t 'dual condition' -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/live/risk_manager_service/exit_enforcement.rb spec/services/live/risk_manager_service_spec.rb
git commit -m "feat: align 5-second structure invalidation with dual condition

enforce_structure_invalidation_for now checks options-aware dual
condition (underlying_move_pct + premium_drop_pct) when configured.
Falls back to legacy StructureInvalidationRule when not configured."
```

---

## Chunk 2: Exit Tuning — SL/TP, Trailing, TP Suppression

### Task 5: Update SL/TP/percentage exit config values

**Files:**
- Modify: `config/algo.yml:194-201`
- Modify: `config/profiles/exit_testing.yml`

Pure config changes — no code modifications needed for SL since `loss_limit_hit?` already reads `risk.sl_pct`.

- [ ] **Step 1: Update algo.yml risk section**

In `config/algo.yml`, change lines 194-201:

```yaml
risk:
  sl_pct: 0.06 # -6% STOP LOSS (was 0.12)
  tp_pct: 0.12 # +12% TAKE PROFIT (was 0.50)
  per_trade_risk_pct: 0.15

  # --- Percentage-based PnL Exit ---
  percentage_pnl_exit:
    enabled: true
    target_pct: 0.15 # 15% safety net (was 0.30)
```

Also find the `trailing:` section in algo.yml (under `risk:` or `exit:`) and update `activation_pct` to match the institutional trailing early_trigger:

```yaml
  trailing:
    activation_pct: 0.025  # was 0.035 — match institutional_trailing.nifty.early_trigger
    drawdown_pct: 0.018    # was 0.025 — match tier 1 adaptive drawdown
```

**Why:** `UnifiedExitChecker.build_exit_config` reads `risk.trailing.activation_pct` for the trailing activation threshold. This must be 0.025 to match the institutional trailing `early_trigger`, otherwise TP suppression (Task 6) will use the wrong activation value (0.035 instead of 0.025).

- [ ] **Step 2: Update exit_testing.yml to mirror**

Add to `config/profiles/exit_testing.yml` under the existing `risk:` section:

```yaml
risk:
  sl_pct: 0.06
  tp_pct: 0.12
  percentage_pnl_exit:
    enabled: true
    target_pct: 0.15
  time_regimes:
    chop_decay:
      allow_entries: true
      min_adx: 14.0
  edge_failure_detector:
    max_consecutive_sls: 3
    consecutive_sl_pause_minutes: 30
    rolling_window_size: 6
    rolling_window_threshold_rupees: -5000
    pause_duration_minutes: 30
```

- [ ] **Step 3: Verify config loads correctly**

Run: `bundle exec rails runner "puts AlgoConfig.fetch[:risk].slice(:sl_pct, :tp_pct).inspect"`
Expected: `{sl_pct: 0.06, tp_pct: 0.12}`

- [ ] **Step 4: Run existing exit tests to verify no regressions**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -v`
Expected: All existing tests pass (some may need threshold adjustments if they hardcoded old values)

- [ ] **Step 5: Commit**

```bash
git add config/algo.yml config/profiles/exit_testing.yml
git commit -m "config: tighten SL to 6%, TP to 12%, percentage exit to 15%

Options buying optimizations: tighter SL cuts losers fast (premium decay
makes recovery unlikely), realistic TP captures actual option moves,
15% percentage exit acts as safety net."
```

---

### Task 6: Add TP suppression when trailing is active

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb:161-167` (`profit_target_hit?`)
- Test: `spec/services/live/unified_exit_checker_spec.rb`

When trailing has been armed (peak profit exceeded activation threshold) AND current profit >= TP threshold, suppress the hard TP to let trailing manage the exit for runners.

- [ ] **Step 1: Write the failing test**

```ruby
# In spec/services/live/unified_exit_checker_spec.rb
describe '#profit_target_hit? with trailing suppression' do
  let(:config) do
    {
      stop_loss: { type: 'static', value: 0.06 },
      take_profit: 0.12,
      trailing: { enabled: true, type: 'adaptive', activation_profit: 0.025, drop_threshold: 0.018 },
      early_exit: { enabled: false, profit_threshold: 0.07 },
      premium_momentum_failure: { enabled: false },
      time_based: { enabled: false, exit_time: '15:20' }
    }
  end

  before do
    # CRITICAL: Clear cached exit_config before mocking
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)
    allow(described_class).to receive(:exit_config).and_return(config)
  end

  context 'when trailing is armed and profit exceeds TP' do
    let(:tracker) do
      instance_double(PositionTracker,
        id: 1,
        entry_price: 100.0,
        quantity: 100,
        meta: {},
        high_water_mark_pnl: 2000.0  # peak = 2000/10000 = 20% > activation 2.5%
      )
    end
    let(:snapshot) { { pnl_pct: 0.15, ltp: 115.0, pnl: 1500, hwm_pnl: 2000 } }

    it 'suppresses TP and returns false' do
      result = described_class.send(:profit_target_hit?, tracker, snapshot)
      expect(result).to be false
    end
  end

  context 'when trailing is NOT armed and profit exceeds TP' do
    let(:tracker) do
      instance_double(PositionTracker,
        id: 1,
        entry_price: 100.0,
        quantity: 100,
        meta: {},
        high_water_mark_pnl: 500.0
      )
    end
    let(:snapshot) { { pnl_pct: 0.13, ltp: 113.0, pnl: 1300, hwm_pnl: 1300 } }

    it 'triggers TP normally' do
      result = described_class.send(:profit_target_hit?, tracker, snapshot)
      expect(result).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'trailing suppression' -v`
Expected: FAIL — current `profit_target_hit?` doesn't check trailing state

- [ ] **Step 3: Implement TP suppression**

In `app/services/live/unified_exit_checker.rb`, modify `profit_target_hit?` (lines 161-167):

```ruby
      def profit_target_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f
        tp = config[:take_profit].to_f

        return false unless pnl_pct >= tp

        # Suppress TP when trailing is armed — let trailing manage runners
        if trailing_armed?(tracker, snapshot, config)
          Rails.logger.debug { "[UnifiedExitChecker] TP suppressed for #{tracker.id} — trailing armed, pnl=#{(pnl_pct * 100).round(2)}%" }
          return false
        end

        true
      end

      def trailing_armed?(tracker, snapshot, config)
        return false unless config[:trailing][:enabled]

        activation = config[:trailing][:activation_profit].to_f
        return false unless activation.positive?

        # Check if peak profit has exceeded activation threshold
        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?

        hwm = snapshot[:hwm_pnl].to_f
        peak_profit_pct = hwm / entry_value
        peak_profit_pct >= activation
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'trailing suppression' -v`
Expected: PASS

- [ ] **Step 5: Run full exit checker suite**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -v`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/services/live/unified_exit_checker.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: suppress TP when trailing is armed for options runners

When trailing activation threshold has been exceeded (peak profit >=
activation_pct), suppress the hard TP exit to let trailing manage
the position. Allows momentum runners to capture full trend."
```

---

### Task 7: Add adaptive trailing drawdown tiers to institutional trailing

**Files:**
- Modify: `config/algo.yml:244-266` (institutional_trailing section)
- Modify: `app/services/positions/trailing_config.rb` (parse adaptive_drawdown, select tier)
- Test: `spec/services/positions/trailing_config_spec.rb`

Extend the institutional trailing config with `adaptive_drawdown` tiers that widen allowed drawdown as peak profit increases.

- [ ] **Step 1: Update institutional trailing config in algo.yml**

Replace lines 244-266:

```yaml
  # Institutional Trailing System (3-Phase) with Adaptive Drawdown
  # Calibrated for options buying: tighter early, wider for momentum runners
  institutional_trailing:
    enabled: true
    session_aware: true           # Tighten trail distance in afternoon (0.75x after 13:00)
    expiry_day_tightening: 0.60   # 60% of normal trail on expiry day (Thursday)

    nifty:
      early_trigger: 0.025        # Phase 1: Survival (+2.5% profit → -6% SL)
      early_sl_offset: -0.06
      breakeven_trigger: 0.05     # Phase 2: Breakeven at +5%
      activation_trigger: 0.10    # Phase 3: HWM Trailing at +10%
      trailing_distance: 0.018    # Base trailing distance (tier 1)
      adaptive_drawdown:          # Tiered drawdown: widens with momentum
        - { min_profit: 0.025, drawdown: 0.018 }  # 2.5-10%: tight
        - { min_profit: 0.10, drawdown: 0.022 }   # 10-20%: moderate
        - { min_profit: 0.20, drawdown: 0.025 }   # 20-35%: wider
        - { min_profit: 0.35, drawdown: 0.030 }   # 35%+: widest
    sensex:
      early_trigger: 0.025
      early_sl_offset: -0.06
      breakeven_trigger: 0.05
      activation_trigger: 0.10
      trailing_distance: 0.018
      adaptive_drawdown:
        - { min_profit: 0.025, drawdown: 0.018 }
        - { min_profit: 0.10, drawdown: 0.022 }
        - { min_profit: 0.20, drawdown: 0.025 }
        - { min_profit: 0.35, drawdown: 0.030 }
    banknifty:
      early_trigger: 0.06         # Phase 1: Survival (+6% profit → -15% SL)
      early_sl_offset: -0.15      # Wider SL — BN is more volatile
      breakeven_trigger: 0.18     # Phase 2: Breakeven at +18%
      activation_trigger: 0.25    # Phase 3: HWM Trailing at +25%
      trailing_distance: 0.35     # 35% from HWM (conservative — last-week-only trades)
```

- [ ] **Step 2: Write failing test for adaptive drawdown selection**

```ruby
# In spec/services/positions/trailing_config_spec.rb
describe '.adaptive_drawdown_for_peak' do
  let(:tiers) do
    [
      { min_profit: 0.025, drawdown: 0.018 },
      { min_profit: 0.10, drawdown: 0.022 },
      { min_profit: 0.20, drawdown: 0.025 },
      { min_profit: 0.35, drawdown: 0.030 }
    ]
  end

  it 'returns tier 1 drawdown for peak profit of 5%' do
    expect(described_class.adaptive_drawdown_for_peak(0.05, tiers)).to eq(0.018)
  end

  it 'returns tier 2 drawdown for peak profit of 15%' do
    expect(described_class.adaptive_drawdown_for_peak(0.15, tiers)).to eq(0.022)
  end

  it 'returns tier 3 drawdown for peak profit of 25%' do
    expect(described_class.adaptive_drawdown_for_peak(0.25, tiers)).to eq(0.025)
  end

  it 'returns tier 4 drawdown for peak profit of 40%' do
    expect(described_class.adaptive_drawdown_for_peak(0.40, tiers)).to eq(0.030)
  end

  it 'returns nil for peak profit below first tier' do
    expect(described_class.adaptive_drawdown_for_peak(0.01, tiers)).to be_nil
  end

  it 'returns nil for empty tiers' do
    expect(described_class.adaptive_drawdown_for_peak(0.05, [])).to be_nil
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/services/positions/trailing_config_spec.rb -t 'adaptive_drawdown_for_peak' -v`
Expected: FAIL — method doesn't exist yet

- [ ] **Step 4: Implement adaptive_drawdown_for_peak**

In `app/services/positions/trailing_config.rb`, add the method:

```ruby
    # Select the appropriate drawdown threshold based on peak profit level.
    # Uses highest tier whose min_profit the peak has exceeded.
    # Returns nil if peak is below all tiers or tiers are empty.
    # @param peak_profit_pct [Float] Peak profit percentage (DECIMAL, e.g. 0.15 for 15%)
    # @param tiers [Array<Hash>] Array of { min_profit: Float, drawdown: Float }
    # @return [Float, nil] Drawdown threshold (DECIMAL) or nil
    def adaptive_drawdown_for_peak(peak_profit_pct, tiers)
      return nil if tiers.nil? || tiers.empty?

      selected = nil
      tiers.each do |tier|
        min_profit = tier[:min_profit] || tier['min_profit']
        drawdown = tier[:drawdown] || tier['drawdown']
        next unless min_profit && drawdown

        selected = drawdown.to_f if peak_profit_pct.to_f >= min_profit.to_f
      end
      selected
    end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/services/positions/trailing_config_spec.rb -t 'adaptive_drawdown_for_peak' -v`
Expected: PASS

- [ ] **Step 6: Wire adaptive_drawdown_for_peak into trailing_stop_hit?**

The `trailing_stop_hit?` method in `unified_exit_checker.rb` currently uses `Orders::Analyzer` for NIFTY/BANKNIFTY/SENSEX (lines 176-218). The adaptive drawdown needs to be integrated into this path. Modify the NIFTY/SENSEX/BANKNIFTY branch to consult adaptive drawdown tiers when institutional trailing is configured.

In `app/services/live/unified_exit_checker.rb`, within `trailing_stop_hit?` (after line 185 where `peak_profit_pct` is computed), add an adaptive drawdown override:

```ruby
          # Check adaptive drawdown from institutional trailing config
          index_key = tracker.meta&.dig('index_key')&.downcase
          inst_trailing = AlgoConfig.fetch.dig(:risk, :institutional_trailing, index_key&.to_sym) || {}
          adaptive_tiers = inst_trailing[:adaptive_drawdown]

          if adaptive_tiers.is_a?(Array) && adaptive_tiers.any?
            allowed_dd = Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
            if allowed_dd && peak_profit_pct > 0
              # Calculate drop from peak as fraction
              current_drop_from_peak = (snapshot[:hwm_pnl].to_f - snapshot[:pnl].to_f)
              hwm = snapshot[:hwm_pnl].to_f
              if hwm.positive?
                drop_pct = current_drop_from_peak / hwm * peak_profit_pct
                if drop_pct >= allowed_dd
                  Rails.logger.info("[UnifiedExitChecker] ADAPTIVE_TRAILING hit for #{tracker.order_no}: drop=#{(drop_pct * 100).round(2)}% > allowed=#{(allowed_dd * 100).round(2)}%")
                  return true
                end
              end
            end
          end
```

This is inserted BEFORE the `Orders::Analyzer` block so adaptive drawdown is checked first. If adaptive drawdown triggers, it returns true immediately. If not (e.g., tiers not configured for BANKNIFTY), falls through to the existing `Orders::Analyzer` logic.

- [ ] **Step 7: Write test for adaptive drawdown integration in trailing_stop_hit?**

```ruby
# In spec/services/live/unified_exit_checker_spec.rb
describe 'adaptive trailing drawdown in trailing_stop_hit?' do
  before do
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)
  end

  let(:tracker) do
    instance_double(PositionTracker,
      id: 1,
      symbol: 'NIFTY24MAR24000CE',
      entry_price: 100.0,
      quantity: 100,
      meta: { 'index_key' => 'NIFTY' },
      high_water_mark_pnl: 1500.0
    )
  end

  context 'when drop from peak exceeds adaptive tier drawdown' do
    let(:snapshot) { { pnl_pct: 0.12, ltp: 112.0, pnl: 1200, hwm_pnl: 1500 } }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          institutional_trailing: {
            nifty: {
              adaptive_drawdown: [
                { min_profit: 0.025, drawdown: 0.018 },
                { min_profit: 0.10, drawdown: 0.022 }
              ]
            }
          },
          trailing: { activation_pct: 0.025, drawdown_pct: 0.018 }
        }
      })
    end

    it 'triggers adaptive trailing exit' do
      config = { trailing: { enabled: true, type: 'adaptive', activation_profit: 0.025, drop_threshold: 0.018 } }
      allow(described_class).to receive(:exit_config).and_return(config)
      result = described_class.send(:trailing_stop_hit?, tracker, snapshot)
      # peak_profit_pct = 1500/10000 = 15%, tier 2 (drawdown 0.022)
      # drop = (1500-1200)/1500 * 0.15 = 0.03 > 0.022 → should trigger
      expect(result).to be true
    end
  end
end
```

- [ ] **Step 8: Run tests**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb -t 'adaptive trailing drawdown' -v`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/services/positions/trailing_config.rb app/services/live/unified_exit_checker.rb config/algo.yml spec/services/positions/trailing_config_spec.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: add adaptive trailing drawdown tiers to institutional trailing

4-tier adaptive drawdown that widens with momentum:
2.5-10% → 1.8%, 10-20% → 2.2%, 20-35% → 2.5%, 35%+ → 3.0%.
Based on peak profit (never tightens back). Wired into trailing_stop_hit?
for NIFTY/SENSEX/BANKNIFTY. Institutional trailing triggers tightened
for options: earlier activation, tighter SL."
```

---

## Chunk 3: Entry Strengthening

### Task 8: Update entry quality filter config (ADX, min_score, session overrides)

**Files:**
- Modify: `config/algo.yml:865-882` (entry_quality section)
- Modify: `config/profiles/exit_testing.yml`

- [ ] **Step 1: Update entry_quality config in algo.yml**

Replace lines 865-882:

```yaml
entry_quality:
  enforce: true                      # false = log-only mode (no blocking)
  min_score: 55                      # minimum quality score to enter (was 40)
  gates:
    min_adx: 25                      # hard gate: minimum ADX value (was 20)
    block_choppy_regime: true        # hard gate: block CHOPPY regime
    min_body_ratio: 0.40             # hard gate: minimum candle body/range ratio
    require_momentum_confirm: true   # hard gate: close must be beyond Supertrend level
  scoring:
    candle_body_weight: 25           # max points for candle body strength
    adx_strength_weight: 20          # max points for ADX bonus
    bos_weight: 20                   # max points for break of structure
    range_expansion_weight: 20       # max points for range expansion
    momentum_weight: 15              # max points for momentum strength
  session_overrides:                 # Session-specific threshold overrides
    chop_decay:                      # 11:30-13:45 IST (from risk.time_regimes)
      min_score: 60
      gates:
        min_adx: 30
  index_overrides:
    SENSEX:
      min_adx: 25                    # SENSEX keeps global minimum (was 22)
```

- [ ] **Step 2: Update exit_testing.yml**

Add session overrides and updated thresholds to `config/profiles/exit_testing.yml`:

```yaml
entry_quality:
  enforce: false
  min_score: 55
  gates:
    min_adx: 25
  session_overrides:
    chop_decay:
      min_score: 60
      gates:
        min_adx: 30
```

- [ ] **Step 3: Verify config loads**

Run: `bundle exec rails runner "puts AlgoConfig.fetch[:entry_quality].inspect"`
Expected: Shows min_score: 55, gates min_adx: 25, session_overrides with chop_decay

- [ ] **Step 4: Commit**

```bash
git add config/algo.yml config/profiles/exit_testing.yml
git commit -m "config: tighten entry quality to ADX>=25, min_score 55, S3 overrides

Raise ADX gate from 20 to 25, quality score from 40 to 55.
Add chop_decay (11:30-13:45) session override requiring ADX>=30 and
min_score 60. Reduces low-quality entries that bleed option premium."
```

---

### Task 9: Add session-aware overrides to EntryQualityFilter

**Files:**
- Modify: `app/services/signal/entry_quality_filter.rb:66-80` (`load_config` method)
- Test: `spec/services/signal/entry_quality_filter_spec.rb`

Add session detection: read `risk.time_regimes` boundaries, check `Time.current` against them, apply matching `session_overrides` to config.

- [ ] **Step 1: Write the failing test**

```ruby
# In spec/services/signal/entry_quality_filter_spec.rb
describe 'session-aware overrides' do
  let(:base_config) do
    {
      entry_quality: {
        enforce: true,
        min_score: 55,
        gates: { min_adx: 25, block_choppy_regime: true, min_body_ratio: 0.40, require_momentum_confirm: true },
        scoring: { candle_body_weight: 25, adx_strength_weight: 20, bos_weight: 20, range_expansion_weight: 20, momentum_weight: 15 },
        session_overrides: {
          chop_decay: { min_score: 60, gates: { min_adx: 30 } }
        },
        index_overrides: {}
      },
      risk: {
        time_regimes: {
          open_expansion: { start: '09:15', end: '09:45' },
          trend_continuation: { start: '09:45', end: '11:30' },
          chop_decay: { start: '11:30', end: '13:45' },
          close_gamma: { start: '13:45', end: '15:15' }
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(base_config)
    allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
  end

  context 'during chop_decay session (12:00 IST)' do
    before do
      travel_to Time.zone.parse('2026-03-16 12:00:00 +05:30')
    end

    it 'applies chop_decay session overrides (min_adx: 30)' do
      # ADX 27 passes global gate (25) but fails chop_decay gate (30)
      result = described_class.evaluate(
        series: build_series([build_candle(open: 95, high: 115, low: 90, close: 110)]),
        supertrend_result: build_supertrend(100.0),
        adx_value: 27,
        direction: :bullish,
        regime: 'TRENDING',
        index_key: 'NIFTY'
      )
      expect(result[:pass]).to be false
      expect(result[:reject_reason]).to eq('min_adx')
    end

    it 'uses min_score 60 during chop_decay (rejects score that would pass global 55)' do
      # Verify the internal config was loaded with session override by checking
      # that a score between 55-59 is rejected (would pass global min_score 55)
      # We test this by calling load_config directly and checking the threshold
      config = described_class.send(:load_config, 'NIFTY')
      expect(config[:min_score]).to eq(60)
      expect(config[:gates][:min_adx]).to eq(30)
    end
  end

  context 'during trend_continuation session (10:00 IST)' do
    before do
      travel_to Time.zone.parse('2026-03-16 10:00:00 +05:30')
    end

    it 'uses standard thresholds (min_adx: 25)' do
      result = described_class.evaluate(
        series: build_series([build_candle(open: 95, high: 115, low: 90, close: 110)]),
        supertrend_result: build_supertrend(100.0),
        adx_value: 27,
        direction: :bullish,
        regime: 'TRENDING',
        index_key: 'NIFTY'
      )
      # ADX 27 passes standard gate (25) — no chop_decay override
      expect(result[:reject_reason]).not_to eq('min_adx')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb -t 'session-aware overrides' -v`
Expected: FAIL — no session detection in load_config

- [ ] **Step 3: Implement session detection in load_config**

In `app/services/signal/entry_quality_filter.rb`, modify `load_config`:

```ruby
      def load_config(index_key)
        raw = AlgoConfig.fetch[:entry_quality] || {}
        config = deep_symbolize(DEFAULTS.deep_merge(raw))

        # Apply session-specific overrides based on current time
        apply_session_overrides!(config)

        # Apply index-specific overrides (check Symbol and String keys)
        overrides = config.dig(:index_overrides, index_key.to_sym) ||
                    config.dig(:index_overrides, index_key.to_s) || {}
        overrides = deep_symbolize(overrides)

        if overrides[:min_adx]
          config[:gates] = config[:gates].merge(min_adx: overrides[:min_adx])
        end

        config
      end

      def apply_session_overrides!(config)
        session_overrides = config[:session_overrides]
        return unless session_overrides.is_a?(Hash)

        current_session = detect_current_session
        return unless current_session

        override = session_overrides[current_session.to_sym]
        return unless override.is_a?(Hash)

        override = deep_symbolize(override)

        # Apply min_score override
        config[:min_score] = override[:min_score] if override[:min_score]

        # Apply gate overrides (merge to preserve other gates)
        if override[:gates].is_a?(Hash)
          config[:gates] = config[:gates].merge(override[:gates])
        end
      end

      def detect_current_session
        time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)
        return nil unless time_regimes.is_a?(Hash)

        now = Time.current.in_time_zone('Asia/Kolkata')
        current_time = now.strftime('%H:%M')

        time_regimes.each do |session_name, regime_cfg|
          next unless regime_cfg.is_a?(Hash)

          start_time = regime_cfg[:start] || regime_cfg['start']
          end_time = regime_cfg[:end] || regime_cfg['end']
          next unless start_time && end_time

          return session_name.to_sym if current_time >= start_time.to_s && current_time < end_time.to_s
        end

        nil
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb -t 'session-aware overrides' -v`
Expected: PASS

- [ ] **Step 5: Run full entry quality filter suite**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb -v`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/services/signal/entry_quality_filter.rb spec/services/signal/entry_quality_filter_spec.rb
git commit -m "feat: session-aware entry quality overrides

EntryQualityFilter now detects current market session using
risk.time_regimes config boundaries and applies session_overrides.
During chop_decay (11:30-13:45), requires ADX>=30 and min_score 60."
```

---

### Task 10: Change cooldown from per-symbol to per-index

**Files:**
- Modify: `app/services/entries/guards/cooldown_guard.rb:8`
- Modify: `app/models/position_tracker.rb:630-634`
- Modify: `app/services/entries/entry_guard.rb:429-434`
- Test: `spec/services/entries/guards/cooldown_guard_spec.rb`

Currently cooldown tracks `"reentry:#{symbol}"` (per option contract). Change to `"reentry:index:#{index_key}"` so entering any NIFTY option starts cooldown for all NIFTY entries.

- [ ] **Step 1: Write the failing test**

```ruby
# In spec/services/entries/guards/cooldown_guard_spec.rb (create if needed)
require 'rails_helper'

RSpec.describe Entries::Guards::CooldownGuard do
  describe '.call' do
    let(:context) do
      {
        pick: { symbol: 'NIFTY24MAR24000CE' },
        index_cfg: { key: 'NIFTY', cooldown_sec: 180 }
      }
    end

    context 'when a different NIFTY option was recently entered' do
      before do
        # Simulate cooldown set for the NIFTY index (not this specific symbol)
        Rails.cache.write('reentry:index:NIFTY', Time.current, expires_in: 8.hours)
      end

      after { Rails.cache.delete('reentry:index:NIFTY') }

      it 'blocks entry due to index-level cooldown' do
        result = described_class.call(context)
        expect(result).to include(blocked: /cooldown active/)
      end
    end

    context 'when no recent NIFTY entry exists' do
      before { Rails.cache.delete('reentry:index:NIFTY') }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entries/guards/cooldown_guard_spec.rb -v`
Expected: FAIL — cooldown uses per-symbol key

- [ ] **Step 3: Update cooldown_guard.rb to use index key**

```ruby
# frozen_string_literal: true

module Entries
  module Guards
    class CooldownGuard
      class << self
        def call(context)
          index_key = context[:index_cfg][:key]
          cooldown = context[:index_cfg][:cooldown_sec].to_i
          return EntryGuardPipeline::PASS unless EntryGuard.cooldown_active_for_index?(index_key, cooldown)

          { blocked: "cooldown active for #{index_key}" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Add cooldown_active_for_index? to EntryGuard**

In `app/services/entries/entry_guard.rb`, near `cooldown_active?` (line 429), add:

```ruby
      def cooldown_active_for_index?(index_key, cooldown)
        return false if index_key.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:index:#{index_key}")
        last.present? && (Time.current - last) < cooldown
      end
```

- [ ] **Step 5: Update register_cooldown! in PositionTracker to also set index key**

In `app/models/position_tracker.rb`, modify `register_cooldown!` (lines 630-634):

```ruby
  def register_cooldown!
    return if symbol.blank?

    # Legacy per-symbol cooldown (kept for backward compat)
    Rails.cache.write("reentry:#{symbol}", Time.current, expires_in: 8.hours)

    # Per-index cooldown — entering any option on this index starts cooldown for all
    index_key = meta&.dig('index_key')
    if index_key.present?
      Rails.cache.write("reentry:index:#{index_key}", Time.current, expires_in: 8.hours)
    end
  end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/services/entries/guards/cooldown_guard_spec.rb -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/services/entries/guards/cooldown_guard.rb app/services/entries/entry_guard.rb app/models/position_tracker.rb spec/services/entries/guards/cooldown_guard_spec.rb
git commit -m "feat: change cooldown from per-symbol to per-index

Entering any NIFTY option now starts the 180s cooldown for ALL NIFTY
entries, preventing rapid-fire entries on different strikes.
Per-symbol cooldown key retained for backward compatibility."
```

---

### Task 11: Create MaxConcurrentGuard and register in pipeline

**Files:**
- Create: `app/services/entries/guards/max_concurrent_guard.rb`
- Modify: `app/services/entries/entry_guard_pipeline.rb:35-36`
- Modify: `config/algo.yml` (add max_concurrent_per_index to index configs)
- Test: `spec/services/entries/guards/max_concurrent_guard_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/entries/guards/max_concurrent_guard_spec.rb
require 'rails_helper'

RSpec.describe Entries::Guards::MaxConcurrentGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY', max_concurrent_per_index: 2 }
      }
    end

    context 'when fewer than max concurrent positions exist' do
      before do
        allow(PositionTracker).to receive_message_chain(:active, :where, :count).and_return(1)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when max concurrent positions reached' do
      before do
        allow(PositionTracker).to receive_message_chain(:active, :where, :count).and_return(2)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /max_concurrent_positions/)
      end
    end

    context 'when max_concurrent_per_index not configured' do
      let(:context) { { index_cfg: { key: 'NIFTY' } } }

      it 'allows entry (no limit)' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entries/guards/max_concurrent_guard_spec.rb -v`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Create MaxConcurrentGuard**

```ruby
# app/services/entries/guards/max_concurrent_guard.rb
# frozen_string_literal: true

module Entries
  module Guards
    class MaxConcurrentGuard
      class << self
        def call(context)
          max = context[:index_cfg][:max_concurrent_per_index]
          return EntryGuardPipeline::PASS unless max

          index_key = context[:index_cfg][:key]
          current_count = PositionTracker.active.where("(meta->>'index_key') = ?", index_key.to_s).count

          return EntryGuardPipeline::PASS if current_count < max.to_i

          { blocked: "max_concurrent_positions (#{current_count}/#{max}) for #{index_key}" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Register in pipeline**

In `app/services/entries/entry_guard_pipeline.rb`, add `Guards::MaxConcurrentGuard` after `Guards::DailyLimitsGuard` (line 35):

```ruby
    def default_handlers
      [
        Guards::CircuitBreakerGuard,
        Guards::BosContractGuard,
        Guards::TimeRegimeGuard,
        Guards::BankniftyLastWeekGuard,
        Guards::EdgeFailureGuard,
        Guards::DailyLimitsGuard,
        Guards::MaxConcurrentGuard,     # NEW: max concurrent positions per index
        Guards::InstrumentLookupGuard,
        Guards::ExposureGuard,
        Guards::CooldownGuard,
        Guards::LtpResolutionGuard
      ]
    end
```

- [ ] **Step 5: Add max_concurrent_per_index to index configs in algo.yml**

Find each index config in `config/algo.yml` and add `max_concurrent_per_index: 2`. The indices are at different line numbers — search for `- key: NIFTY`, `- key: BANKNIFTY`, and `- key: SENSEX` and add the field to each.

```yaml
  - key: NIFTY
    # ... existing fields ...
    max_concurrent_per_index: 2

  - key: SENSEX
    # ... existing fields ...
    max_concurrent_per_index: 2

  - key: BANKNIFTY
    # ... existing fields ...
    max_concurrent_per_index: 2
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/services/entries/guards/max_concurrent_guard_spec.rb -v`
Expected: PASS

- [ ] **Step 7: Run full pipeline test to verify no regressions**

Run: `bundle exec rspec spec/services/entries/ -v`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add app/services/entries/guards/max_concurrent_guard.rb app/services/entries/entry_guard_pipeline.rb config/algo.yml spec/services/entries/guards/max_concurrent_guard_spec.rb
git commit -m "feat: add MaxConcurrentGuard — max 2 positions per index

Prevents stacking correlated risk by limiting concurrent open positions
to 2 per index. Inserted after DailyLimitsGuard in the entry pipeline.
Uses meta.index_key for per-index counting."
```

---

## Final Verification

### Task 12: Full regression test and final config verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec -v`
Expected: 0 new failures (pre-existing failures may exist)

- [ ] **Step 2: Run rubocop on changed files**

Run: `bundle exec rubocop app/services/live/unified_exit_checker.rb app/services/signal/entry_quality_filter.rb app/services/entries/guards/max_concurrent_guard.rb app/services/entries/guards/cooldown_guard.rb app/services/entries/entry_guard_pipeline.rb app/services/positions/trailing_config.rb app/services/entries/entry_guard.rb app/models/position_tracker.rb app/services/live/risk_manager_service/exit_enforcement.rb`
Expected: No new offenses

- [ ] **Step 3: Verify config loads end-to-end**

Run:
```bash
bundle exec rails runner "
  cfg = AlgoConfig.fetch
  puts 'SL: ' + cfg.dig(:risk, :sl_pct).to_s
  puts 'TP: ' + cfg.dig(:risk, :tp_pct).to_s
  puts 'PnL exit: ' + cfg.dig(:risk, :percentage_pnl_exit, :target_pct).to_s
  puts 'SI enabled: ' + cfg.dig(:risk, :exits, :structure_invalidation, :enabled).to_s
  puts 'SI underlying_move: ' + cfg.dig(:risk, :exits, :structure_invalidation, :underlying_move_pct).to_s
  puts 'SI premium_drop: ' + cfg.dig(:risk, :exits, :structure_invalidation, :premium_drop_pct).to_s
  puts 'EQ min_score: ' + cfg.dig(:entry_quality, :min_score).to_s
  puts 'EQ min_adx: ' + cfg.dig(:entry_quality, :gates, :min_adx).to_s
  puts 'NIFTY adaptive_drawdown: ' + cfg.dig(:risk, :institutional_trailing, :nifty, :adaptive_drawdown).to_s
"
```

Expected output:
```
SL: 0.06
TP: 0.12
PnL exit: 0.15
SI enabled: true
SI underlying_move: 0.01
SI premium_drop: 0.05
EQ min_score: 55
EQ min_adx: 25
NIFTY adaptive_drawdown: [{min_profit: 0.025, drawdown: 0.018}, ...]
```

- [ ] **Step 4: Commit any rubocop fixes**

```bash
git add app/services/live/unified_exit_checker.rb app/services/signal/entry_quality_filter.rb app/services/entries/guards/max_concurrent_guard.rb app/services/entries/guards/cooldown_guard.rb app/services/entries/entry_guard_pipeline.rb app/services/positions/trailing_config.rb app/services/entries/entry_guard.rb app/models/position_tracker.rb app/services/live/risk_manager_service/exit_enforcement.rb
git commit -m "style: fix rubocop offenses in options optimization changes"
```

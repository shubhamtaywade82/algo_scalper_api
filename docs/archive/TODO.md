Code Review Report: algo_scalper_api

  Type: Rails Trading Application

  Scope: Full repository review

  Project patterns detected: Heavy service object architecture, Redis caching for PnL, Event-driven risk management, Paper/live trading modes

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    🔴 CRITICAL — Must Fix Before Production

      1. Time Zone Vulnerabilities — Multiple Files
      Files: Multiple locations across app/services/

      Issue: Using Time.now, Time.parse, Date.today instead of Time.zone/Time.current

      Impact: Incorrect time calculations in production (server timezone vs app timezone mismatch)

      Found in:
      - app/services/auto_exp/results_store.rb:28 — Time.now
      - app/services/analytics/live_adapter.rb:17,26 — Time.now
      - app/services/market/regime_state.rb:26,49 — Time.now
      - app/services/context/builder.rb:23 — Date.today
      - app/lib/dhan/auth/strategies/renew.rb:37 — Time.parse
      - app/lib/dhan/auth/strategies/totp.rb:39 — Time.parse
      - app/lib/dhan/auth/strategies/authority.rb:37 — Time.parse
      - app/services/backtest/api_loader.rb:79 — Time.parse
      - app/services/backtest/data_loader.rb:18 — Time.parse

      Fix:
      ```ruby
      # Before
      Time.now
      Date.today
      Time.parse(ts)

After
Time.current
Time.zone.today
Time.zone.parse(ts)
```
Rule: rails-best-practices/security-timeouts.md » security-timeouts.md

      2. Ignored save/update Return Values
      Files: Multiple

      Issue: Calling save or update without checking return value or using bang methods

      Impact: Silent failures when validations fail or DB errors occur

      Found in:
      - app/models/public_ip_log.rb:34 — log.save if log.changed? (return value ignored)
      - app/models/trading_signal.rb:105 — update(...) without bang or check

      Fix:
      ```ruby
      # Before
      log.save if log.changed?
      update(metadata: …)

After
log.save! if log.changed?
update!(metadata: …)
# OR
unless update(metadata: …)
  errors.add(:base, “Failed to update…”)
end
```
Rule: rails-best-practices/security-timeouts.md » security-timeouts.md

      3. Potential N+1 in Positions Controller
      File: app/controllers/api/positions_controller.rb:20-23

      Issue: Using .map after includes but accessing associations that may not be preloaded

      Code:
      ruby
      def open_positions
        PositionTracker
          .active
          .includes(:watchable, :instrument)
          .map { |tracker| Positions::Serializer.open(tracker) }
      end

      Risk: If Positions::Serializer.open accesses other associations, N+1 will occur

      Fix: Verify serializer only uses preloaded associations, or add strict_loading to detect violations

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    🟠 PERFORMANCE — High Impact

      4. .count Called Multiple Times on Same Relation
      File: app/controllers/api/positions_controller.rb:77-83

      Issue: Multiple .count queries on same base relation instead of using SQL aggregation

      Code:
      ruby
      def filter_summary
        base = PositionTracker.exited.where(exited_at: filter_date.all_day)
        {
          total:        base.count,
          profit_count: base.where("last_pnl_rupees > 0").count,
          loss_count:   base.where("last_pnl_rupees < 0").count,
          total_pnl:    base.sum(:last_pnl_rupees).to_f.round(2)
        }
      end

      Impact: 4 separate SQL queries instead of 1

      Fix:
      ruby
      def filter_summary
        base = PositionTracker.exited.where(exited_at: filter_date.all_day)
        counts = base.group(Arel.sql("CASE WHEN last_pnl_rupees > 0 THEN 'profit' WHEN last_pnl_rupees < 0 THEN 'loss' ELSE 'breakeven' END")).count
        total_pnl = base.sum(:last_pnl_rupees)
        {
          date:         filter_date.to_s,
          total:        counts.sum { |_, v| v },
          profit_count: counts['profit'] || 0,
          loss_count:   counts['loss'] || 0,
          total_pnl:    total_pnl.to_f.round(2)
        }
      end

      Rule: rails-best-practices/active-record.md » active-record.md

      5. Missing find_each for Large Dataset Iteration
      File: app/jobs/clear_carried_overnight_positions_job.rb:16

      Issue: Loading all trackers into memory with .to_a

      Code:
      ruby
      trackers = PositionTracker.active.where(created_at: ...today_start).to_a

      Risk: Memory exhaustion if thousands of positions exist

      Fix:
      ruby
      PositionTracker.active.where(created_at: ...today_start).find_each do |tracker|
        # process each tracker
      end

      Rule: rails-best-practices/active-record.md » active-record.md

      6. .where in Model Instance Method (Breaks Preloading)
      Files:
      - app/models/instrument.rb:185-188
      - app/models/derivative.rb:185-188

      Code:
      ruby
      PositionTracker.active.where(
        "(watchable_type = 'Instrument' AND watchable_id = ?) OR instrument_id = ?",
        id, id
      ).where(security_id: security).sum(:quantity).to_i

      Impact: Cannot be preloaded; triggers N+1 when called in loops

      Fix: Extract to filtered association or class method with explicit preload instructions

      Rule: rails-best-practices/active-record.md » active-record.md

      7. No Index on Foreign Keys
      Files: Multiple models

      Issue: Missing database indexes on foreign key columns

      Found:
      - position_trackers.watchable_id (polymorphic)
      - position_trackers.instrument_id
      - trade_analytics.tracker_id
      - trade_telemetries.tracker_id

      Fix: Add migration:
      ruby
      add_index :position_trackers, [:watchable_type, :watchable_id]
      add_index :position_trackers, :instrument_id
      add_index :trade_analytics, :tracker_id
      add_index :trade_telemetries, :tracker_id

      Rule: rails-best-practices/active-record.md » active-record.md

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    🟡 PROJECT CONSISTENCY

      8. Inconsistent Service Calling Convention
      Observation: Mixed patterns found:
      - Some services use .call (e.g., Positions::ActiveCache.instance)
      - Some use .new(...).method pattern
      - Some are instantiated and called directly

      Recommendation: Standardize on one pattern across all services:
      ```ruby
      # Preferred (consistent with ApplicationService pattern)
      ResultService.call(params)

Alternative (also fine, but be consistent)
ResultService.new(params).execute
```

      9. Inconsistent Error Handling in Controllers
      File: app/controllers/api/positions_controller.rb:68-71

      Issue: Some methods rescue and return defaults, others don’t

      Code:
      ruby
      def available_dates
        # ... rescue StandardError
        [ Time.zone.today.to_s ]
      end

      Recommendation: Either use a base controller with standardized error handling, or apply consistent rescue patterns across all controller methods

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    🔵 BEST PRACTICES

      10. Missing Strong Parameters in Controllers
      File: app/controllers/api/settings_controller.rb:31 (update_bulk)

      Issue: No strong parameter filtering shown

      Risk: Mass assignment vulnerability

      Fix: Add explicit parameter filtering:
      ruby
      def settings_params
        params.require(:settings).permit(
          # list all allowed keys
        )
      end

      Rule: rails-best-practices/security-timeouts.md » security-timeouts.md

      11. Long Methods (>50 lines)
      Files: Multiple services with very long methods

      Found:
      - app/services/live/risk_manager_service.rb — Multiple 100+ line methods
      - app/services/entries/entry_guard.rb — 900+ line file
      - app/services/options/chain_analyzer.rb — 1200+ line file
      - app/services/backtest_service_with_no_trade_engine.rb — 700+ line file
      - app/services/signal/engine.rb — 1100+ line file

      Recommendation: Extract into smaller, focused methods (target < 20 lines) or use service objects to split responsibilities

      Rule: solid-ruby/clean-code.md » references/clean-code.md

      12. Missing Test Coverage for Critical Services
      Observation: Many core services lack spec files:
      - app/services/live/risk_manager_service.rb — No matching spec
      - app/services/entries/entry_guard.rb — Partial coverage
      - app/services/options/chain_analyzer.rb — No spec
      - app/services/signal/engine.rb — No spec

      Recommendation: Prioritize unit tests for:
      1. Risk management logic
      2. Entry/exit guards
      3. Options pricing calculations
      4. Signal generation engine

      Rule: solid-ruby/tdd.md » references/tdd.md

      13. Magic Numbers in Business Logic
      Files: Multiple

      Issue: Hardcoded values without constants or configuration

      Examples:
      - app/services/live/risk_manager_service.rb:12 — LOOP_INTERVAL = 5
      - app/services/entries/entry_guard.rb:8-11 — Some constants, but many magic numbers remain

      Fix: Extract to configuration or well-named constants:
      ```ruby
      # Before
      if pnl_change > 0.05
        # 5% milestone

After
PNL_MILESTONE_THRESHOLD = 0.05
if pnl_change > PNL_MILESTONE_THRESHOLD
```

      14. God Classes Detected
      Files:
      - app/services/options/chain_analyzer.rb — 1200+ lines
      - app/services/signal/engine.rb — 1100+ lines
      - app/services/entries/entry_guard.rb — 900+ lines
      - app/models/position_tracker.rb — 500+ lines

      Recommendation: Split by responsibility:
      - ChainAnalyzer → StrikeSelector, LtpFetcher, ScoringEngine, ChainBuilder
      - Signal::Engine → IndexAnalyzer, StrategySelector, SignalValidator, PickGenerator
      - EntryGuard → Individual guard classes (already partially done with guards/)

      Rule: solid-ruby/code-smells.md » references/code-smells.md

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    ⚪ STYLE

      15. Inconsistent Blank Lines Around private
      Observation: Some files have blank lines around private, others don’t

      Rule: ruby-style/flow-of-control » https://rubystyle.guide/#empty-lines-between-defs

      16. Comments Describing What Instead of Why
      Files: Multiple

      Example:
      ruby
      # Calculate PnL from exit price
      def calculate_pnl(exit_price)
        # ...
      end

      Fix: Either remove comment or explain why this calculation differs from others

      Rule: solid-ruby/clean-code.md » references/clean-code.md

      17. Missing frozen_string_literal in Some Files
      Observation: Most files have it, but check all lib/ and service files

      Rule: ruby-style/source-code-layout » https://rubystyle.guide/#encoding

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Summary

  ┌─────────────────┬───────┬────────────────┐
  │ Severity        │ Count │ Must Fix       │
  ├─────────────────┼───────┼────────────────┤
  │ 🔴 Critical     │ 3+    │ ✅ Yes         │
  ├─────────────────┼───────┼────────────────┤
  │ 🟠 Performance  │ 4     │ ✅ Yes         │
  ├─────────────────┼───────┼────────────────┤
  │ 🟡 Consistency  │ 2     │ ⚠️ Recommended  │
  ├─────────────────┼───────┼────────────────┤
  │ 🔵 Best         │ 5     │ ⚠️ Recommended  │
  │ Practice        │       │                │
  ├─────────────────┼───────┼────────────────┤
  │ ⚪ Style        │ 3     │ ❌ Optional    │
  └─────────────────┴───────┴────────────────┘

    Pre-Merge Blockers:
    1. Time zone fixes — Replace all Time.now, Date.today, Time.parse with zone-aware methods
    2. Bang methods — Use save!/update! or check return values
    3. N+1 queries — Add missing indexes, use find_each, optimize .count calls

    Technical Debt (Schedule for Next Sprint):
    1. God class refactoring (ChainAnalyzer, Signal::Engine, EntryGuard)
    2. Test coverage for critical services
    3. Service calling convention standardization
    4. Extract magic numbers to constants/configuration

◈────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

    Verdict: 🔧 NEEDS FIXES — Critical issues must be resolved before production deployment.

    Want me to apply the fixes for the critical and performance issues?
# Regime-driven Signal Generation + Per-Regime Exit Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate `Research::Signal` rows from underlying regime state (trend/volatility for trending entries, liquidity-sweep for ranging entries) instead of ORB-only, score them through the already-fixed `Research::Pipeline`/`Research::TradeScorer` path, and report which of the 14 `exit_simulations` strategies performs best *within each regime bucket*.

**Architecture:** Three new files, zero changes to existing `Research::` code. `Research::RegimeSignalGenerator` walks trading days at four fixed checkpoint times, classifies regime via the already-existing `Research::UnderlyingContextSnapshot`/`Research::ContextClassifier`, and creates `Research::Signal` rows. `Research::Pipeline` (unmodified) scores them into `OptionCandidate`s with `exit_simulations`. `Research::RegimeExitReport` groups scored candidates by regime dimension and reuses `Research::ResearchReportGenerator.evaluate_exits` for the stats math.

**Tech Stack:** Ruby 3.3.4, Rails 8 API-only, RSpec, PostgreSQL (jsonb columns).

## Global Constraints

- Everything stays inside `Research::` — no live-trading wiring, no changes to `app/services/orders/`, `app/services/live/`, `app/services/entries/`, or any LOCKED layer per project CLAUDE.md.
- Zero changes to `Research::Pipeline`, `Research::TradeScorer`, `Research::CandidateExitSimulator`, `Research::ExitCaptureAnalyzer`, `Research::UnderlyingContextSnapshot`, `Research::ContextClassifier`, `Research::SignalSnapshotBuilder`, `Research::ResearchReportGenerator` — every task only reads/calls these, never edits them.
- Checkpoint-based signal generation only: 4 fixed times/day (`09:45`, `11:30`, `13:30`, `15:00`), no continuous per-bar scanner, no cooldown/state-machine logic.
- ATM only — `Research::Pipeline.run(..., max_distance: 0)` always. `Research::RegimeExitReport` filters to `strike_label: "ATM"` before grouping (mixing strike labels inside one `evaluate_exits` call silently zeroes out mismatched rows — see Task 2 rationale).
- All regime hash keys are strings (`"trend"`, `"volatility_regime"`, `"liquidity_sweep"`, `"close"`, `"regime"`) — confirmed by reading `Research::ContextClassifier#classify` and `Research::UnderlyingContextSnapshot.at` directly. Do not use symbol keys when reading a snapshot in-memory.
- `exit_simulations` (jsonb column) round-trips through Postgres with **string** keys on both the strategy name and the nested field names after `ActiveRecord` reload — `Research::ResearchReportGenerator.evaluate_exits` expects **symbol** keys (it `.dig`s with `:return_pct` etc.). Any code reading a persisted `exit_simulations` value for `evaluate_exits` must call `.deep_symbolize_keys` first.
- No new database migrations — `Research::Signal.metadata` (jsonb) and `Research::OptionCandidate.exit_simulations` (jsonb, added last session) already exist and are sufficient.

---

### Task 1: `Research::RegimeSignalGenerator`

**Files:**
- Create: `app/services/research/regime_signal_generator.rb`
- Test: `spec/services/research/regime_signal_generator_spec.rb`

**Interfaces:**
- Consumes: `Research::UnderlyingContextSnapshot.at(symbol:, timestamp:)` → `{}` or a hash with string keys `"close"`, `"regime"` (itself a string-keyed hash with `"trend"`, `"volatility_regime"`, `"liquidity_sweep"`, etc. — see `Research::ContextClassifier#classify`); `Market::Calendar.trading_day?(date)` → boolean; `Research::Signal.find_by(underlying_symbol:, signal_timestamp:, strategy_name:)` for idempotency; `Research::SignalSnapshotBuilder.build(underlying_symbol:, signal_timestamp:, direction:, spot_price:, strategy_name:, metadata:)` (existing, confirmed signature — `app/services/research/signal_snapshot_builder.rb:12`) for creation.
- Produces: `Research::RegimeSignalGenerator.run(symbol:, from_date:, to_date:, checkpoint_times: ["09:45","11:30","13:30","15:00"])` → `Array<Research::Signal>`. Every created signal has `strategy_name: "regime_scan"` and `metadata["regime"]` set to the full regime hash from that checkpoint (used by Task 2).

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/research/regime_signal_generator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::RegimeSignalGenerator do
  describe '.run' do
    before do
      allow(Market::Calendar).to receive(:trading_day?).and_return(true)
    end

    def stub_snapshot(regime_overrides, close: 25_000.0)
      regime = {
        "market_structure" => "range", "recent_bos" => false, "recent_choch" => false,
        "trend" => "neutral", "volatility_regime" => "stable", "momentum" => "neutral_momentum",
        "volume_regime" => "average", "time_context" => "morning", "vwap_relation" => "at_vwap",
        "liquidity_sweep" => "none", "opening_range_breakout" => "inside_range", "gap" => "none"
      }.merge(regime_overrides)

      allow(Research::UnderlyingContextSnapshot).to receive(:at)
        .and_return({ "close" => close, "regime" => regime })
    end

    it 'creates a bullish signal when trend is trending and volatility is expanding' do
      stub_snapshot("trend" => "strong_bullish", "volatility_regime" => "expanding")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals.size).to eq(1)
      expect(signals.first.direction).to eq("bullish")
      expect(signals.first.strategy_name).to eq("regime_scan")
      expect(signals.first.spot_price.to_f).to eq(25_000.0)
      expect(signals.first.metadata["regime"]["trend"]).to eq("strong_bullish")
    end

    it 'creates a bearish signal when trend is trending bearish and volatility is expanding' do
      stub_snapshot("trend" => "weak_bearish", "volatility_regime" => "expanding")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bearish")
    end

    it 'does not signal on a trending regime without volatility expansion' do
      stub_snapshot("trend" => "strong_bullish", "volatility_regime" => "stable")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'creates a bullish signal on a neutral (ranging) trend with a sell-side liquidity sweep' do
      stub_snapshot("trend" => "neutral", "liquidity_sweep" => "sell_side_sweep")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bullish")
    end

    it 'creates a bearish signal on a neutral (ranging) trend with a buy-side liquidity sweep' do
      stub_snapshot("trend" => "neutral", "liquidity_sweep" => "buy_side_sweep")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bearish")
    end

    it 'does not signal on a neutral trend with no liquidity sweep' do
      stub_snapshot("trend" => "neutral", "liquidity_sweep" => "none")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'skips checkpoints with an empty snapshot (insufficient candle history)' do
      allow(Research::UnderlyingContextSnapshot).to receive(:at).and_return({})

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'skips non-trading days' do
      allow(Market::Calendar).to receive(:trading_day?).and_return(false)
      stub_snapshot("trend" => "strong_bullish", "volatility_regime" => "expanding")

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'is idempotent across repeated runs for the same symbol/date/checkpoint' do
      stub_snapshot("trend" => "strong_bullish", "volatility_regime" => "expanding")

      first_run = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                       checkpoint_times: ["09:45"])
      second_run = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                        checkpoint_times: ["09:45"])

      expect(first_run.map(&:id)).to eq(second_run.map(&:id))
      expect(Research::Signal.where(strategy_name: "regime_scan").count).to eq(1)
    end

    it 'does not raise and continues when one checkpoint fails' do
      call_count = 0
      allow(Research::UnderlyingContextSnapshot).to receive(:at) do
        call_count += 1
        raise "boom" if call_count == 1

        { "close" => 25_000.0, "regime" => { "trend" => "strong_bullish", "volatility_regime" => "expanding" } }
      end

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                     checkpoint_times: ["09:45", "11:30"])

      expect(signals.size).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/research/regime_signal_generator_spec.rb`
Expected: FAIL with `uninitialized constant Research::RegimeSignalGenerator`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/research/regime_signal_generator.rb
# frozen_string_literal: true

module Research
  # Generates Research::Signal rows from underlying regime state instead of
  # a fixed entry rule (ORB). Checkpoint-based (4 fixed times/day, aligned to
  # Research::ContextClassifier's own time_context bucket boundaries) rather
  # than a continuous per-bar scanner — no cooldown/state-machine needed
  # since checkpoints are already ~2hrs apart.
  class RegimeSignalGenerator
    STRATEGY_NAME = "regime_scan"
    DEFAULT_CHECKPOINT_TIMES = %w[09:45 11:30 13:30 15:00].freeze
    TRENDING_BULLISH = %w[strong_bullish weak_bullish].freeze
    TRENDING_BEARISH = %w[strong_bearish weak_bearish].freeze

    class << self
      def run(symbol:, from_date:, to_date:, checkpoint_times: DEFAULT_CHECKPOINT_TIMES)
        symbol = symbol.to_s.upcase
        from = Date.parse(from_date.to_s)
        to = Date.parse(to_date.to_s)

        (from..to).select { |date| Market::Calendar.trading_day?(date) }.flat_map do |date|
          checkpoint_times.filter_map { |time_str| signal_for(symbol, date, time_str) }
        end
      end

      private

      def signal_for(symbol, date, time_str)
        timestamp = Time.zone.parse("#{date} #{time_str}")
        snapshot = Research::UnderlyingContextSnapshot.at(symbol: symbol, timestamp: timestamp)
        return nil if snapshot.blank? || snapshot["close"].blank?

        direction = direction_for(snapshot["regime"] || {})
        return nil if direction.nil?

        existing = Research::Signal.find_by(
          underlying_symbol: symbol, signal_timestamp: timestamp, strategy_name: STRATEGY_NAME
        )
        return existing if existing

        Research::SignalSnapshotBuilder.build(
          underlying_symbol: symbol, signal_timestamp: timestamp, direction: direction,
          spot_price: snapshot["close"], strategy_name: STRATEGY_NAME,
          metadata: { "regime" => snapshot["regime"], "checkpoint" => time_str }
        )
      rescue StandardError => e
        Rails.logger.error(
          "[Research::RegimeSignalGenerator] #{symbol} #{date} #{time_str} failed: #{e.class}: #{e.message}"
        )
        nil
      end

      def direction_for(regime)
        trend = regime["trend"]
        volatility = regime["volatility_regime"]
        sweep = regime["liquidity_sweep"]

        return "bullish" if TRENDING_BULLISH.include?(trend) && volatility == "expanding"
        return "bearish" if TRENDING_BEARISH.include?(trend) && volatility == "expanding"
        return "bullish" if trend == "neutral" && sweep == "sell_side_sweep"
        return "bearish" if trend == "neutral" && sweep == "buy_side_sweep"

        nil
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/research/regime_signal_generator_spec.rb`
Expected: PASS (10 examples, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/research/regime_signal_generator.rb spec/services/research/regime_signal_generator_spec.rb
git commit -m "Add Research::RegimeSignalGenerator for regime-driven signal creation"
```

---

### Task 2: `Research::RegimeExitReport`

**Files:**
- Create: `app/services/research/regime_exit_report.rb`
- Test: `spec/services/research/regime_exit_report_spec.rb`

**Interfaces:**
- Consumes: `candidate.research_signal.strategy_name` (String), `candidate.research_signal.metadata["regime"]` (String-keyed hash, from Task 1), `candidate.strike_label` (String), `candidate.exit_simulations` (jsonb — String-keyed after reload, must `.deep_symbolize_keys` before use), `Research::ResearchReportGenerator.evaluate_exits(trades, strike_label:)` → `Hash{Symbol => Hash}` where each value has `:avg_return_pct`, `:win_rate_pct`, `:sharpe_ratio`, `:profit_factor`, `:edge_score`, etc. (confirmed by reading the method directly — see `app/services/research/research_report_generator.rb:101-156`).
- Produces: `Research::RegimeExitReport.call(scope:, dimensions: ["trend","volatility_regime","liquidity_sweep"])` → `Array<Hash>` sorted best-bucket-first, each `{ context: {...}, sample_size: Integer, strategies: {strategy_name_symbol => stats_hash, ...} (sorted best-first), best_strategy: Symbol|nil, best_strategy_return_pct: Float|nil }`.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/research/regime_exit_report_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::RegimeExitReport do
  def make_candidate(strategy_name:, strike_label: "ATM", regime: {}, exit_simulations: {})
    signal = Research::Signal.create!(
      underlying_symbol: "NIFTY", signal_timestamp: Time.zone.parse("2026-07-13 09:45:00"),
      direction: "bullish", spot_price: 25_000.0, strategy_name: strategy_name,
      metadata: { "regime" => regime }
    )
    Research::OptionCandidate.create!(
      research_signal: signal, underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "CE",
      strike_label: strike_label, strike_distance: 0, entry_model: "next_candle_open",
      status: "scored", exit_simulations: exit_simulations
    )
  end

  def exits_with(fixed_30_return:, hold_to_close_return:)
    Research::ExitCaptureAnalyzer::STRATEGY_NAMES.index_with do |name|
      return_pct = name == :fixed_30 ? fixed_30_return : (name == :hold_to_close ? hold_to_close_return : 0.0)
      {
        "exit_price" => 100.0, "exit_time" => "2026-07-13T10:00:00+05:30", "exit_reason" => "market_close",
        "holding_time_minutes" => 30, "capture_efficiency" => 0.5, "opportunity_retention_ratio" => 0.5,
        "lost_profit_points" => 1.0, "leakage_time" => 0, "leakage_speed" => 0.0, "giveback_pct" => 0.0,
        "return_pct" => return_pct, "win" => return_pct.positive?
      }
    end.stringify_keys
  end

  describe '.call' do
    it 'groups scored regime_scan candidates by regime dimensions and ranks strategies by avg_return_pct' do
      make_candidate(
        strategy_name: "regime_scan", regime: { "trend" => "strong_bullish", "volatility_regime" => "expanding" },
        exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: -5.0)
      )
      make_candidate(
        strategy_name: "regime_scan", regime: { "trend" => "strong_bullish", "volatility_regime" => "expanding" },
        exit_simulations: exits_with(fixed_30_return: 20.0, hold_to_close_return: -5.0)
      )

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                      dimensions: %w[trend volatility_regime])

      expect(buckets.size).to eq(1)
      bucket = buckets.first
      expect(bucket[:context]).to eq("trend" => "strong_bullish", "volatility_regime" => "expanding")
      expect(bucket[:sample_size]).to eq(2)
      expect(bucket[:best_strategy]).to eq(:fixed_30)
      expect(bucket[:best_strategy_return_pct]).to eq(15.0)
      expect(bucket[:strategies][:fixed_30][:avg_return_pct]).to eq(15.0)
      expect(bucket[:strategies][:hold_to_close][:avg_return_pct]).to eq(-5.0)
    end

    it 'separates buckets by distinct regime context' do
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "strong_bullish" },
                      exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "neutral" },
                      exit_simulations: exits_with(fixed_30_return: -10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                      dimensions: %w[trend])

      expect(buckets.size).to eq(2)
      expect(buckets.map { |b| b[:context]["trend"] }).to contain_exactly("strong_bullish", "neutral")
    end

    it 'excludes candidates whose signal did not come from the regime scanner' do
      make_candidate(strategy_name: "manual_rake_run", regime: { "trend" => "strong_bullish" },
                      exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                      dimensions: %w[trend])

      expect(buckets).to be_empty
    end

    it 'excludes candidates with an unrecognized strike_label' do
      make_candidate(strategy_name: "regime_scan", strike_label: "ATM+1", regime: { "trend" => "strong_bullish" },
                      exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                      dimensions: %w[trend])

      expect(buckets).to be_empty
    end

    it 'defaults missing regime dimensions to "unknown"' do
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "strong_bullish" },
                      exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                      dimensions: %w[trend volatility_regime])

      expect(buckets.first[:context]).to eq("trend" => "strong_bullish", "volatility_regime" => "unknown")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/research/regime_exit_report_spec.rb`
Expected: FAIL with `uninitialized constant Research::RegimeExitReport`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/research/regime_exit_report.rb
# frozen_string_literal: true

module Research
  # Ranks Research::ExitCaptureAnalyzer's exit strategies per regime bucket,
  # instead of one aggregate number across every trade — shaped like
  # Research::ExpectancyReport (group by regime dimension) but reusing
  # Research::ResearchReportGenerator.evaluate_exits for the stats math
  # instead of reimplementing win-rate/expectancy/Sharpe a third time.
  #
  # Scoped to strike_label "ATM" only: evaluate_exits looks up every trade's
  # exits under one caller-given strike_label key, so mixing strike labels
  # inside a single call would silently zero out rows whose real strike
  # doesn't match instead of excluding them cleanly.
  class RegimeExitReport
    REGIME_STRATEGY_NAME = "regime_scan"
    ATM_STRIKE_LABEL = "ATM"
    DEFAULT_DIMENSIONS = %w[trend volatility_regime liquidity_sweep].freeze

    class << self
      def call(scope:, dimensions: DEFAULT_DIMENSIONS)
        rows = scope.where(strike_label: ATM_STRIKE_LABEL)
                    .includes(:research_signal)
                    .filter_map { |candidate| row_for(candidate, dimensions) }

        rows
          .group_by { |row| row[:context] }
          .map { |context, group| summarize(context, group) }
          .sort_by { |bucket| -(bucket[:best_strategy_return_pct] || -Float::INFINITY) }
      end

      private

      def row_for(candidate, dimensions)
        return nil unless candidate.research_signal.strategy_name == REGIME_STRATEGY_NAME
        return nil if candidate.exit_simulations.blank?

        regime = candidate.research_signal.metadata["regime"] || {}
        context = dimensions.index_with { |dim| regime[dim] || "unknown" }

        { context: context, strike_label: candidate.strike_label, exit_simulations: candidate.exit_simulations }
      end

      def summarize(context, group)
        trades = group.map do |row|
          { strikes: { row[:strike_label] => { exits: row[:exit_simulations].deep_symbolize_keys } } }
        end

        strategies = Research::ResearchReportGenerator.evaluate_exits(trades, strike_label: group.first[:strike_label])
        ranked = strategies.sort_by { |_name, stats| -(stats[:avg_return_pct] || -Float::INFINITY) }.to_h
        best = ranked.first

        {
          context: context,
          sample_size: group.size,
          strategies: ranked,
          best_strategy: best&.first,
          best_strategy_return_pct: best&.last&.dig(:avg_return_pct)
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/research/regime_exit_report_spec.rb`
Expected: PASS (5 examples, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/research/regime_exit_report.rb spec/services/research/regime_exit_report_spec.rb
git commit -m "Add Research::RegimeExitReport to rank exit strategies per regime bucket"
```

---

### Task 3: `research:run_regime_scan` rake task

**Files:**
- Modify: `lib/tasks/research.rake` (append a third task inside the existing `namespace :research do ... end` block, after `run_board_lifecycle`)

**Interfaces:**
- Consumes: `Research::RegimeSignalGenerator.run` (Task 1), `Research::Pipeline.run(signal:, expiry_flags:, max_distance: 0)` (existing, unmodified), `Research::RegimeExitReport.call` (Task 2).
- Produces: a rake task callable as `bundle exec rake 'research:run_regime_scan[NIFTY,2026-06-01,2026-07-01]'`. No return value consumed elsewhere — this is the end-user entry point.

- [ ] **Step 1: Add the rake task**

Open `lib/tasks/research.rake`. Add this block immediately before the final `end` that closes `namespace :research do`:

```ruby
  desc "Generate regime-driven signals over a date range and rank exit strategies per regime bucket"
  task :run_regime_scan, %i[symbol from_date to_date expiry_flag] => :environment do |_t, args|
    symbol = args[:symbol].presence || raise(ArgumentError, "symbol is required")
    from_date = args[:from_date].presence || raise(ArgumentError, "from_date is required")
    to_date = args[:to_date].presence || raise(ArgumentError, "to_date is required")
    expiry_flag = args[:expiry_flag].presence || "WEEK"

    puts "\n#{'=' * 100}"
    puts "Regime scan — #{symbol} #{from_date} to #{to_date}"
    puts '=' * 100

    signals = Research::RegimeSignalGenerator.run(symbol: symbol, from_date: from_date, to_date: to_date)
    puts "#{signals.size} regime-driven signals generated."

    signals.each do |signal|
      Research::Pipeline.run(signal: signal, expiry_flags: [expiry_flag], max_distance: 0)
    end

    buckets = Research::RegimeExitReport.call(scope: Research::OptionCandidate.where(status: "scored"))

    if buckets.empty?
      puts "No scored candidates produced (check symbol/date range/candle data availability)."
      next
    end

    buckets.each do |bucket|
      puts "\n#{'-' * 100}"
      puts "Regime: #{bucket[:context].map { |k, v| "#{k}=#{v}" }.join(', ')} (n=#{bucket[:sample_size]})"
      puts '-' * 100
      printf("%-20s %10s %8s %8s %10s\n", "Strategy", "AvgRet%", "Win%", "PF", "Sharpe")
      bucket[:strategies].each do |name, stats|
        printf("%-20s %10s %8s %8s %10s\n",
               name, stats[:avg_return_pct], stats[:win_rate_pct], stats[:profit_factor], stats[:sharpe_ratio])
      end
    end
  end
```

- [ ] **Step 2: Verify the rake task loads without syntax errors**

Run: `bundle exec rake -T research`
Expected: lists all three tasks, including:
```
rake research:run_regime_scan[symbol,from_date,to_date,expiry_flag]  # Generate regime-driven signals over a date range and rank exit strategies per regime bucket
```

- [ ] **Step 3: Manual smoke test against real data (requires DhanHQ credentials in the running environment — not available in the sandbox this plan was written in)**

Run: `bundle exec rake 'research:run_regime_scan[NIFTY,2026-06-01,2026-06-05]'`
Expected: prints "N regime-driven signals generated," then one ranked strategy table per regime bucket encountered. If DhanHQ credentials are unavailable, this step is deferred — note it as a known gap rather than skipping silently.

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/research.rake
git commit -m "Add research:run_regime_scan rake task wiring signal generation through to the regime exit report"
```

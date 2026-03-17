# Automated Calibration System — Core Pipeline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the automated weekly calibration pipeline — migration, services, job, and API — that fetches ATM±1 option history, detects regime shifts, generates a config patch, and persists it as a pending `CalibrationRun` for human approval.

**Architecture:** `WeeklyCalibrationJob` → `Options::AutoCalibrator` (orchestrator) → `ExpiryCalendar`, `DhanHQ::Models::ExpiredOptionsData`, `HistoricalCalibrationEngine` × 3 → `StrikeAggregator` → `RegimeDetector` → `CalibrationConfigPatchBuilder` → `CalibrationRun.create!` → `CalibrationNotifier`. `Api::CalibrationRunsController` exposes the runs for listing and applying. `apply!` on the model writes to `Setting.put` + `AlgoConfig.reset!`.

**Tech Stack:** Rails 8, Ruby 3.3.4, PostgreSQL (JSONB), Solid Queue, DhanHQ `ExpiredOptionsData` API, Telegram (existing `CalibrationNotifier` pattern), RSpec + WebMock.

---

## Chunk 1: Data Layer

### Task 1: Migration — `calibration_runs` table

**Files:**
- Create: `db/migrate/20260317000001_create_calibration_runs.rb`
- Test: `spec/models/calibration_run_spec.rb` (schema only for now)

**Background:** This table stores one record per calibration run. `proposed_patch` is a JSONB blob of algo.yml-compatible overrides. `raw_stats` stores the weighted CE/PE aggregates from `StrikeAggregator`. `is_regime_shift` flags runs triggered by a detected regime change.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260317000001_create_calibration_runs.rb
# frozen_string_literal: true

class CreateCalibrationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :calibration_runs do |t|
      t.string   :symbol,        null: false
      t.integer  :weeks_analyzed, null: false, default: 52
      t.string   :strike_mode,   null: false, default: 'atm_plus_minus'
      t.jsonb    :raw_stats,     null: false, default: {}
      t.jsonb    :proposed_patch, null: false, default: {}
      t.boolean  :is_regime_shift, null: false, default: false
      t.string   :regime_reason
      t.datetime :applied_at
      t.string   :applied_by

      t.timestamps
    end

    add_index :calibration_runs, %i[symbol created_at]
    add_index :calibration_runs, :applied_at
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
rails db:migrate
```

Expected: Migration runs cleanly. `calibration_runs` table visible in `rails dbconsole`.

- [ ] **Step 3: Write a minimal schema spec (no model yet)**

```ruby
# spec/models/calibration_run_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'calibration_runs table' do
  it 'has the expected columns' do
    cols = ActiveRecord::Base.connection.columns(:calibration_runs).map(&:name)
    expect(cols).to include(
      'symbol', 'weeks_analyzed', 'strike_mode',
      'raw_stats', 'proposed_patch',
      'is_regime_shift', 'regime_reason',
      'applied_at', 'applied_by',
      'created_at', 'updated_at'
    )
  end
end
```

- [ ] **Step 4: Run the spec**

```bash
bundle exec rspec spec/models/calibration_run_spec.rb -f d
```

Expected: 1 example, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260317000001_create_calibration_runs.rb \
        db/schema.rb \
        spec/models/calibration_run_spec.rb
git commit -m "feat: add calibration_runs migration"
```

---

### Task 2: `CalibrationRun` model

**Files:**
- Create: `app/models/calibration_run.rb`
- Test: `spec/models/calibration_run_spec.rb` (expand)

**Background:** Key methods are `apply!` (deep-merges `proposed_patch` into `algo_config_overrides` setting, busts caches) and `propose_config!` (no-op pre-versioning; creates `AlgoConfigVersion` when that branch lands). `apply!` must use `Setting.put` (not raw `upsert`) to bust Solid Cache, and must call `AlgoConfig.reset!` to bust the 30s in-process cache. Double-apply raises immediately.

- [ ] **Step 1: Write failing tests for the model**

```ruby
# spec/models/calibration_run_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalibrationRun do
  let(:run) do
    CalibrationRun.create!(
      symbol: 'NIFTY',
      weeks_analyzed: 52,
      strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 },
      proposed_patch: {
        'risk' => {
          'percentage_pnl_exit' => { 'target_pct' => 0.064 },
          'trailing' => { 'activation_pct' => 0.036, 'drawdown_pct' => 0.025 }
        }
      }
    )
  end

  describe 'schema' do
    it 'has the expected columns' do
      cols = ActiveRecord::Base.connection.columns(:calibration_runs).map(&:name)
      expect(cols).to include('symbol', 'raw_stats', 'proposed_patch', 'applied_at')
    end
  end

  describe 'validations' do
    it 'requires symbol' do
      run = CalibrationRun.new(weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
                               raw_stats: {}, proposed_patch: {})
      expect(run).not_to be_valid
      expect(run.errors[:symbol]).to be_present
    end
  end

  describe '#apply!' do
    before do
      allow(Setting).to receive(:put)
      allow(Setting).to receive(:find_by).and_return(nil)
      allow(AlgoConfig).to receive(:reset!)
    end

    it 'writes merged patch via Setting.put' do
      run.apply!
      expect(Setting).to have_received(:put).with('algo_config_overrides', anything)
    end

    it 'calls AlgoConfig.reset! to bust in-process cache' do
      run.apply!
      expect(AlgoConfig).to have_received(:reset!)
    end

    it 'sets applied_at' do
      run.apply!
      expect(run.reload.applied_at).to be_present
    end

    it 'sets applied_by from argument' do
      run.apply!(applied_by: 'telegram')
      expect(run.reload.applied_by).to eq('telegram')
    end

    it 'raises on double-apply' do
      run.update!(applied_at: Time.current)
      expect { run.apply! }.to raise_error(RuntimeError, /already applied/)
    end

    it 'deep-merges proposed_patch over existing overrides' do
      existing = { 'risk' => { 'some_other_key' => 0.9 } }.to_json
      captured = nil
      allow(Setting).to receive(:find_by).and_return(
        instance_double(Setting, value: existing)
      )
      allow(Setting).to receive(:put) { |_k, v| captured = v }

      run2 = CalibrationRun.create!(
        symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
        raw_stats: {}, proposed_patch: { 'risk' => { 'new_key' => 0.1 } }
      )
      run2.apply!

      merged = JSON.parse(captured)
      expect(merged.dig('risk', 'some_other_key')).to eq(0.9)
      expect(merged.dig('risk', 'new_key')).to eq(0.1)
    end
  end

  describe '#propose_config!' do
    it 'is a no-op when AlgoConfigVersion is not defined' do
      hide_const('AlgoConfigVersion') if defined?(AlgoConfigVersion)
      expect { run.propose_config! }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/models/calibration_run_spec.rb -f d
```

Expected: FAIL — `uninitialized constant CalibrationRun`

- [ ] **Step 3: Write the model**

```ruby
# app/models/calibration_run.rb
# frozen_string_literal: true

# == Schema Information
#
# Table name: calibration_runs
#
#  id              :integer   not null, primary key
#  symbol          :string    not null
#  weeks_analyzed  :integer   not null, default: 52
#  strike_mode     :string    not null, default: "atm_plus_minus"
#  raw_stats       :jsonb     not null, default: {}
#  proposed_patch  :jsonb     not null, default: {}
#  is_regime_shift :boolean   not null, default: false
#  regime_reason   :string
#  applied_at      :datetime
#  applied_by      :string
#  created_at      :datetime  not null
#  updated_at      :datetime  not null
#

class CalibrationRun < ApplicationRecord
  validates :symbol, presence: true

  scope :pending,  -> { where(applied_at: nil) }
  scope :applied,  -> { where.not(applied_at: nil) }

  # Merges proposed_patch into algo_config_overrides and busts both caches.
  # Uses Setting.put (not upsert) so Solid Cache entry for
  # "setting:algo_config_overrides" is busted immediately.
  # Calls AlgoConfig.reset! to bust the 30-second in-process config cache.
  # Raises if already applied (idempotency guard).
  def apply!(applied_by: 'api')
    raise 'already applied' if applied_at.present?

    current = JSON.parse(Setting.find_by(key: 'algo_config_overrides')&.value || '{}')
    # proposed_patch from JSONB is string-keyed; deep_merge is safe
    # (CalibrationConfigPatchBuilder never emits array-valued keys)
    merged = current.deep_merge(proposed_patch.deep_stringify_keys)
    Setting.put('algo_config_overrides', merged.to_json)
    AlgoConfig.reset!
    update!(applied_at: Time.current, applied_by: applied_by)
  end

  # No-op pre-versioning. When AlgoConfigVersion lands, creates a version record.
  # No controller or job changes needed at that point.
  def propose_config!
    return unless defined?(AlgoConfigVersion)

    AlgoConfigVersion.create!(
      name: "calibration-#{symbol.downcase}-#{created_at.strftime('%Y%m%d')}",
      overrides: proposed_patch,
      source: 'calibration',
      calibration_run_id: id
    )
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/models/calibration_run_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Run RuboCop**

```bash
bundle exec rubocop app/models/calibration_run.rb
```

Expected: no offenses (or only expected auto-correctable style notes).

- [ ] **Step 6: Commit**

```bash
git add app/models/calibration_run.rb spec/models/calibration_run_spec.rb
git commit -m "feat: add CalibrationRun model with apply! and propose_config!"
```

---

## Chunk 2: Pure Logic Services

### Task 3: `Options::ExpiryCalendar`

**Files:**
- Create: `app/services/options/expiry_calendar.rb`
- Test: `spec/services/options/expiry_calendar_spec.rb`

**Background:** Replaces the `last_thursday` helper baked into rake tasks and `HistoricalOptionsAnalyzer`. Maps each symbol to its expiry weekday (NIFTY=Thursday=4, SENSEX=Friday=5, both using Ruby's `Date#wday` where Sunday=0). Raises `ArgumentError` for unknown symbols. Returns windows in ascending expiry-date order, oldest first.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/options/expiry_calendar_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ExpiryCalendar do
  describe '.windows' do
    context 'for NIFTY (Thursday expiry)' do
      it 'returns windows with Thursday expiry dates' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 4)
        expect(windows.size).to eq(4)
        windows.each do |w|
          expect(w[:expiry].wday).to eq(4), "expected Thursday, got #{w[:expiry].strftime('%A')}"
        end
      end

      it 'each window spans 6 days ending on expiry (from = expiry - 6.days)' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 2)
        windows.each do |w|
          expect(w[:to]).to eq(w[:expiry])
          expect(w[:from]).to eq(w[:expiry] - 6.days)
        end
      end

      it 'returns windows in ascending order (oldest first)' do
        windows = described_class.windows(symbol: 'NIFTY', weeks: 4)
        dates = windows.map { |w| w[:expiry] }
        expect(dates).to eq(dates.sort)
      end
    end

    context 'for SENSEX (Friday expiry)' do
      it 'returns windows with Friday expiry dates' do
        windows = described_class.windows(symbol: 'SENSEX', weeks: 4)
        windows.each do |w|
          expect(w[:expiry].wday).to eq(5), "expected Friday, got #{w[:expiry].strftime('%A')}"
        end
      end
    end

    context 'when run on the expiry day itself' do
      it 'includes the current week as the most recent window' do
        thursday = Date.new(2026, 3, 12) # A Thursday
        travel_to(thursday) do
          windows = described_class.windows(symbol: 'NIFTY', weeks: 1)
          expect(windows.last[:expiry]).to eq(thursday)
        end
      end
    end

    context 'with an unknown symbol' do
      it 'raises ArgumentError' do
        expect {
          described_class.windows(symbol: 'UNKNOWN', weeks: 4)
        }.to raise_error(ArgumentError, /unknown symbol/)
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/options/expiry_calendar_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::ExpiryCalendar`

- [ ] **Step 3: Write the service**

```ruby
# app/services/options/expiry_calendar.rb
# frozen_string_literal: true

module Options
  # Maps index symbols to expiry weekdays and generates weekly windows.
  # Weekday convention: Date#wday (Sunday=0, Monday=1, ..., Thursday=4, Friday=5)
  # NOT Date#cwday (which starts Monday=1).
  class ExpiryCalendar
    EXPIRY_WEEKDAY = {
      'NIFTY'   => 4, # Thursday
      'SENSEX'  => 5  # Friday
    }.freeze

    # @param symbol [String] 'NIFTY' or 'SENSEX'
    # @param weeks  [Integer] number of past expiry windows to return
    # @return [Array<Hash>] [{expiry: Date, from: Date, to: Date}, ...] oldest first
    def self.windows(symbol:, weeks:)
      wday = EXPIRY_WEEKDAY[symbol.to_s.upcase]
      raise ArgumentError, "unknown symbol: #{symbol} (known: #{EXPIRY_WEEKDAY.keys.join(', ')})" unless wday

      today = Time.zone.today
      # Find most recent past expiry (inclusive of today if today IS expiry day)
      days_since = (today.wday - wday) % 7
      current_expiry = today - days_since.days

      Array.new(weeks) do |i|
        expiry = current_expiry - (i * 7).days
        { expiry: expiry, from: expiry - 6.days, to: expiry }
      end.reverse
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/options/expiry_calendar_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/options/expiry_calendar.rb \
        spec/services/options/expiry_calendar_spec.rb
git commit -m "feat: add Options::ExpiryCalendar"
```

---

### Task 4: `Options::StrikeAggregator`

**Files:**
- Create: `app/services/options/strike_aggregator.rb`
- Test: `spec/services/options/strike_aggregator_spec.rb`

**Background:** Receives three `HistoricalCalibrationEngine#call` result hashes (ATM, OTM1, OTM2) and returns a single weighted `combined_stats` hash in the same format as `engine[:combined]`. Weights: ATM=0.50, OTM1=0.25, OTM2=0.25 (ATM dominates because it's closest to where trades are taken). The `CalibrationConfigPatchBuilder` consumes this output.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/options/strike_aggregator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeAggregator do
  def engine_result(avg_gain:, avg_retrace_abs:, avg_loss_abs:, avg_oc:, oc_stddev: 2.0)
    # Minimal structure matching HistoricalCalibrationEngine#call output
    {
      ce: { avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
            avg_oc: avg_oc, oc_stddev: oc_stddev, avg_entry: 100.0, fee_pct: 0.4, avg_corr_slope: 0.8,
            sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 } },
      pe: { avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
            avg_oc: avg_oc, oc_stddev: oc_stddev, avg_entry: 100.0, fee_pct: 0.4, avg_corr_slope: -0.8,
            sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 } }
    }
  end

  describe '.combine' do
    let(:atm)  { engine_result(avg_gain: 20.0, avg_retrace_abs: 4.0, avg_loss_abs: 8.0, avg_oc: 5.0, oc_stddev: 3.0) }
    let(:otm1) { engine_result(avg_gain: 14.0, avg_retrace_abs: 3.0, avg_loss_abs: 6.0, avg_oc: 3.5, oc_stddev: 2.5) }
    let(:otm2) { engine_result(avg_gain: 10.0, avg_retrace_abs: 2.0, avg_loss_abs: 4.0, avg_oc: 2.5, oc_stddev: 2.0) }

    subject(:result) { described_class.combine(atm_stats: atm, otm1_stats: otm1, otm2_stats: otm2) }

    it 'returns a hash with avg_gain, avg_retrace_abs, avg_loss_abs, avg_oc, oc_stddev' do
      expect(result).to include(:avg_gain, :avg_retrace_abs, :avg_loss_abs, :avg_oc, :oc_stddev)
    end

    it 'weights ATM at 0.50, OTM1 at 0.25, OTM2 at 0.25' do
      # avg_gain: ATM=20, OTM1=14, OTM2=10 → 0.5*20 + 0.25*14 + 0.25*10 = 16.0
      expected_gain = (0.50 * 20.0) + (0.25 * 14.0) + (0.25 * 10.0)
      expect(result[:avg_gain]).to be_within(0.01).of(expected_gain)
    end

    it 'returns avg_retrace_abs weighted correctly' do
      # 0.5*4 + 0.25*3 + 0.25*2 = 3.25
      expected = (0.50 * 4.0) + (0.25 * 3.0) + (0.25 * 2.0)
      expect(result[:avg_retrace_abs]).to be_within(0.01).of(expected)
    end

    it 'returns oc_stddev weighted correctly' do
      # 0.5*3.0 + 0.25*2.5 + 0.25*2.0 = 2.625
      expected = (0.50 * 3.0) + (0.25 * 2.5) + (0.25 * 2.0)
      expect(result[:oc_stddev]).to be_within(0.01).of(expected)
    end

    it 'includes sessions with weighted values' do
      expect(result).to have_key(:sessions)
      expect(result[:sessions]).to include(:morning_oc, :midday_oc, :afternoon_oc)
    end

    context 'when otm2_stats is nil (DhanHQ fetch failed)' do
      it 'falls back to ATM=0.67 OTM1=0.33 weighting' do
        result = described_class.combine(atm_stats: atm, otm1_stats: otm1, otm2_stats: nil)
        # 2/3 * 20 + 1/3 * 14 ≈ 18.0
        expected = (2.0 / 3.0 * 20.0) + (1.0 / 3.0 * 14.0)
        expect(result[:avg_gain]).to be_within(0.1).of(expected)
      end
    end

    context 'when only atm_stats is available' do
      it 'returns ATM stats directly' do
        result = described_class.combine(atm_stats: atm, otm1_stats: nil, otm2_stats: nil)
        expect(result[:avg_gain]).to be_within(0.01).of(20.0)
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/options/strike_aggregator_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::StrikeAggregator`

- [ ] **Step 3: Write the service**

```ruby
# app/services/options/strike_aggregator.rb
# frozen_string_literal: true

module Options
  # Combines HistoricalCalibrationEngine results for ATM, OTM1, OTM2 strikes
  # into a single weighted stats hash for use by CalibrationConfigPatchBuilder.
  #
  # Input: each *_stats is a Hash from HistoricalCalibrationEngine#call, containing
  # :ce and :pe leg summaries (avg_gain, avg_retrace_abs, avg_loss_abs, etc.)
  #
  # Output: a combined stats Hash with the same keys as engine[:combined],
  # weighted across the three strikes. Nil inputs are skipped; weights are
  # redistributed proportionally.
  class StrikeAggregator
    WEIGHTS = { atm: 0.50, otm1: 0.25, otm2: 0.25 }.freeze

    def self.combine(atm_stats:, otm1_stats:, otm2_stats:)
      new(atm: atm_stats, otm1: otm1_stats, otm2: otm2_stats).combine
    end

    def initialize(atm:, otm1:, otm2:)
      @entries = { atm: atm, otm1: otm1, otm2: otm2 }
    end

    def combine
      available = @entries.reject { |_, v| v.nil? }
      return fallback_empty if available.empty?

      # Redistribute weights to available entries
      # normalized: [[:atm, 0.5], [:otm1, 0.25], ...]  — flat pairs, not a Hash
      total_weight = available.keys.sum { |k| WEIGHTS[k] }
      normalized   = available.map { |k, _| [k, WEIGHTS[k] / total_weight] }

      {
        avg_gain:         weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_gain) },
        avg_retrace_abs:  weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_retrace_abs) },
        avg_loss_abs:     weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_loss_abs) },
        avg_oc:           weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_oc) },
        oc_stddev:        weighted_avg(normalized) { |stats| avg_ce_pe(stats, :oc_stddev) },
        sessions: {
          morning_oc:   weighted_avg(normalized) { |stats| avg_session(stats, :morning_oc) },
          midday_oc:    weighted_avg(normalized) { |stats| avg_session(stats, :midday_oc) },
          afternoon_oc: weighted_avg(normalized) { |stats| avg_session(stats, :afternoon_oc) }
        }
      }
    end

    private

    # Available entries: [[:key, normalized_weight], ...]
    def weighted_avg(entries, &block)
      entries.sum { |(key, weight)| weight * block.call(@entries[key]).to_f }.round(4)
    end

    def avg_ce_pe(stats, key)
      ce = stats.dig(:ce, key).to_f
      pe = stats.dig(:pe, key).to_f
      (ce + pe) / 2.0
    end

    def avg_session(stats, session_key)
      ce = stats.dig(:ce, :sessions, session_key).to_f
      pe = stats.dig(:pe, :sessions, session_key).to_f
      (ce + pe) / 2.0
    end

    def fallback_empty
      { avg_gain: 0.0, avg_retrace_abs: 0.0, avg_loss_abs: 0.0, avg_oc: 0.0, oc_stddev: 0.0,
        sessions: { morning_oc: 0.0, midday_oc: 0.0, afternoon_oc: 0.0 } }
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/options/strike_aggregator_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/options/strike_aggregator.rb \
        spec/services/options/strike_aggregator_spec.rb
git commit -m "feat: add Options::StrikeAggregator with weighted multi-strike combining"
```

---

## Chunk 3: Analysis Services

### Task 5: `Options::RegimeDetector`

**Files:**
- Create: `app/services/options/regime_detector.rb`
- Test: `spec/services/options/regime_detector_spec.rb`

**Background:** Compares the just-computed `combined_stats` against ALL prior `CalibrationRun` records for the same symbol using a 1.5-sigma threshold. Checks three metrics: `avg_retrace_abs`, `avg_loss_abs`, and `oc_stddev`. A regime shift is flagged when **any** metric deviates more than `SIGMA_THRESHOLD` (1.5) standard deviations from the historical mean. Requires at least 12 historical runs before detection is active (returns `shift: false` with `reason: 'insufficient_history'` if fewer). Uses only the `raw_stats` column on past runs (not `proposed_patch`).

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/options/regime_detector_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::RegimeDetector do
  def make_run(symbol:, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0)
    CalibrationRun.create!(
      symbol: symbol, weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: {
        'avg_gain'        => 14.0,
        'avg_retrace_abs' => avg_retrace_abs,
        'avg_loss_abs'    => avg_loss_abs,
        'oc_stddev'       => oc_stddev
      },
      proposed_patch: {}
    )
  end

  # Stable combined_stats: all metrics exactly at historical mean → no shift
  let(:stable_stats) { { avg_gain: 14.0, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0 } }

  describe '.check' do
    context 'with fewer than 12 historical runs' do
      before { 11.times { make_run(symbol: 'NIFTY') } }

      it 'returns shift: false with insufficient_history reason' do
        result = described_class.check(symbol: 'NIFTY', combined_stats: stable_stats)
        expect(result[:shift]).to be false
        expect(result[:reason]).to include('insufficient_history')
      end
    end

    context 'with 12+ stable historical runs (all metrics near mean)' do
      before { 12.times { make_run(symbol: 'NIFTY') } }

      it 'returns shift: false when metrics are at the mean' do
        result = described_class.check(symbol: 'NIFTY', combined_stats: stable_stats)
        expect(result[:shift]).to be false
      end
    end

    context 'with a significant avg_retrace_abs spike (> 1.5σ)' do
      before do
        # Establish stable baseline: avg_retrace_abs = 5.0, stddev ≈ 0
        12.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0) }
      end

      it 'returns shift: true when avg_retrace_abs spikes far above mean' do
        # Historical mean = 5.0, stddev ≈ 0 → even small deviation → shift
        # Use a clearly high value: 12.0 (well above any reasonable σ band)
        result = described_class.check(symbol: 'NIFTY',
                                        combined_stats: stable_stats.merge(avg_retrace_abs: 12.0))
        expect(result[:shift]).to be true
        expect(result[:reason]).to include('avg_retrace_abs')
      end
    end

    context 'with a significant oc_stddev spike (> 1.5σ)' do
      before do
        # Varied baseline so stddev > 0: alternating 2.5 and 3.5 → mean 3.0, stddev ≈ 0.5
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 2.5) }
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.5) }
      end

      it 'returns shift: true when oc_stddev is well above 1.5σ' do
        # mean ≈ 3.0, stddev ≈ 0.5 → 1.5σ band ≈ 3.75; 6.0 is clearly outside
        result = described_class.check(symbol: 'NIFTY',
                                        combined_stats: stable_stats.merge(oc_stddev: 6.0))
        expect(result[:shift]).to be true
        expect(result[:reason]).to include('oc_stddev')
      end
    end

    context 'when SENSEX and NIFTY runs coexist' do
      before do
        12.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0) }
        12.times { make_run(symbol: 'SENSEX', avg_retrace_abs: 20.0) }
      end

      it 'uses only the correct symbol history (NIFTY spike tests against NIFTY history)' do
        # NIFTY history: avg_retrace_abs = 5.0, stddev ≈ 0 → 12.0 is a spike
        result = described_class.check(symbol: 'NIFTY',
                                        combined_stats: stable_stats.merge(avg_retrace_abs: 12.0))
        expect(result[:shift]).to be true
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/options/regime_detector_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::RegimeDetector`

- [ ] **Step 3: Write the service**

```ruby
# app/services/options/regime_detector.rb
# frozen_string_literal: true

module Options
  # Detects regime shifts by comparing current calibration stats against
  # ALL prior CalibrationRun records for the symbol using sigma thresholds.
  #
  # A shift is flagged when ANY of the three checked metrics exceeds
  # SIGMA_THRESHOLD standard deviations from the historical mean.
  # Checked metrics: avg_retrace_abs, avg_loss_abs, oc_stddev
  #
  # Requires at least 12 historical runs before detection is active.
  # Returns: { shift: bool, reason: String }
  class RegimeDetector
    SIGMA_THRESHOLD  = 1.5
    MIN_HISTORY_RUNS = 12
    CHECKED_METRICS  = %w[avg_retrace_abs avg_loss_abs oc_stddev].freeze

    def self.check(symbol:, combined_stats:)
      new(symbol: symbol, combined_stats: combined_stats).check
    end

    def initialize(symbol:, combined_stats:)
      @symbol         = symbol.to_s.upcase
      @combined_stats = combined_stats
    end

    def check
      history = CalibrationRun.where(symbol: @symbol).order(created_at: :desc).to_a

      return { shift: false, reason: "insufficient_history (fewer than #{MIN_HISTORY_RUNS} runs)" } \
        if history.size < MIN_HISTORY_RUNS

      CHECKED_METRICS.each do |metric|
        historical_vals = history.map { |r| r.raw_stats[metric].to_f }
        mean  = historical_vals.sum / historical_vals.size
        sigma = stddev(historical_vals)

        next if sigma.zero?

        current_val     = @combined_stats[metric.to_sym].to_f
        deviation_sigma = (current_val - mean).abs / sigma

        if deviation_sigma > SIGMA_THRESHOLD
          direction = current_val > mean ? 'higher' : 'lower'
          reason = "#{metric}: #{current_val.round(2)}% is #{deviation_sigma.round(1)}σ " \
                   "#{direction} than historical mean (#{mean.round(2)}%) — regime shift likely"
          return { shift: true, reason: reason }
        end
      end

      { shift: false, reason: 'stable (all metrics within 1.5σ of historical mean)' }
    end

    private

    def stddev(values)
      return 0.0 if values.size < 2

      mean     = values.sum.to_f / values.size
      variance = values.sum { |v| (v - mean)**2 } / values.size
      Math.sqrt(variance)
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/options/regime_detector_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/options/regime_detector.rb \
        spec/services/options/regime_detector_spec.rb
git commit -m "feat: add Options::RegimeDetector"
```

---

### Task 6: `Options::CalibrationConfigPatchBuilder`

**Files:**
- Create: `app/services/options/calibration_config_patch_builder.rb`
- Test: `spec/services/options/calibration_config_patch_builder_spec.rb`

**Background:** Takes weighted `combined_stats` from `StrikeAggregator` and derives config values using spec formulas (all stats are percentage points, so `/100` converts to decimal). Only emits keys where the proposed value differs from current config by ≥10% to avoid noise. Returns a string-keyed hash (for safe `deep_merge` into `Setting` values). `adaptive_drawdown` is excluded — it is an array-of-hashes that cannot be safely deep-merged.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/options/calibration_config_patch_builder_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationConfigPatchBuilder do
  let(:combined_stats) do
    {
      avg_gain: 14.2,         # percentage points (e.g. 14.2%)
      avg_retrace_abs: 3.1,   # percentage points
      avg_loss_abs: 7.5,      # percentage points
      avg_oc: 4.2,
      sessions: { morning_oc: 2.1, midday_oc: 1.5, afternoon_oc: 0.6 }
    }
  end

  before do
    # Current config returns low values so all derived values will be >10% different
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        percentage_pnl_exit: { target_pct: 0.01 },
        trailing: { activation_pct: 0.01, drawdown_pct: 0.01 },
        profit_floor: { lock_pct: 0.01, trail_pct: 0.01 },
        institutional_trailing: {
          nifty: {
            trailing_distance: 0.01, early_trigger: 0.01,
            breakeven_trigger: 0.01, activation_trigger: 0.01
          },
          sensex: {
            trailing_distance: 0.01, early_trigger: 0.01,
            breakeven_trigger: 0.01, activation_trigger: 0.01
          }
        }
      }
    })
  end

  describe '.build' do
    subject(:patch) { described_class.build(combined_stats: combined_stats, symbol: 'NIFTY') }

    it 'returns a Hash with string keys' do
      expect(patch).to be_a(Hash)
      patch.each_key { |k| expect(k).to be_a(String) }
    end

    it 'derives target_pct as avg_gain * 0.45 / 100 clamped to 0.08..0.35' do
      # 14.2 * 0.45 / 100 = 0.0639
      # clamped to 0.08 (below minimum)
      expected = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      actual = patch.dig('risk', 'percentage_pnl_exit', 'target_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives trailing activation_pct as avg_gain * 0.25 / 100 clamped to 0.020..0.08' do
      # 14.2 * 0.25 / 100 = 0.0355
      expected = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      actual = patch.dig('risk', 'trailing', 'activation_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives trailing drawdown_pct as avg_retrace_abs * 0.80 / 100 clamped to 0.015..0.060' do
      # 3.1 * 0.8 / 100 = 0.0248
      expected = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      actual = patch.dig('risk', 'trailing', 'drawdown_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives institutional trailing_distance as drawdown_pct * 1.1 clamped to 0.030..0.12' do
      drawdown_pct = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      expected = [[drawdown_pct * 1.1, 0.030].max, 0.12].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'trailing_distance')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives early_trigger as activation_pct * 0.85 clamped to 0.020..0.06' do
      activation_pct = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      expected = [[activation_pct * 0.85, 0.020].max, 0.06].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'early_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives breakeven_trigger as activation_pct * 1.5 clamped to 0.040..0.12' do
      activation_pct = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      expected = [[activation_pct * 1.5, 0.040].max, 0.12].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'breakeven_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives activation_trigger as target_pct * 0.55 clamped to 0.08..0.20' do
      target_pct = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      expected = [[target_pct * 0.55, 0.08].max, 0.20].min
      actual = patch.dig('risk', 'institutional_trailing', 'nifty', 'activation_trigger')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'derives profit_floor trail_pct as 1.0 - (avg_retrace_abs * 0.8 / 100) clamped to 0.55..0.92' do
      # 1.0 - (3.1 * 0.8 / 100) = 1.0 - 0.0248 = 0.9752 → clamped to 0.92
      expected = [[1.0 - (3.1 * 0.8 / 100.0), 0.55].max, 0.92].min
      actual = patch.dig('risk', 'profit_floor', 'trail_pct')
      expect(actual).to be_within(0.001).of(expected)
    end

    it 'uses the correct symbol key for institutional_trailing' do
      sensex_patch = described_class.build(combined_stats: combined_stats, symbol: 'SENSEX')
      expect(sensex_patch.dig('risk', 'institutional_trailing')).to have_key('sensex')
      expect(sensex_patch.dig('risk', 'institutional_trailing')).not_to have_key('nifty')
    end
  end

  describe 'change filter (≥10% difference from current)' do
    it 'omits keys where proposed value is within 10% of current config' do
      # Set current config to closely match what the formulas would produce
      target = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          percentage_pnl_exit: { target_pct: target * 1.05 }, # only 5% off → omit
          trailing: { activation_pct: 0.01, drawdown_pct: 0.01 },
          profit_floor: { lock_pct: 0.01, trail_pct: 0.01 },
          institutional_trailing: { nifty: { trailing_distance: 0.01 } }
        }
      })

      patch = described_class.build(combined_stats: combined_stats, symbol: 'NIFTY')
      # target_pct should be absent since difference < 10%
      expect(patch.dig('risk', 'percentage_pnl_exit', 'target_pct')).to be_nil
    end

    it 'returns an empty hash if nothing changed by ≥10%' do
      target     = [[14.2 * 0.45 / 100.0, 0.08].max, 0.35].min
      activation = [[14.2 * 0.25 / 100.0, 0.020].max, 0.08].min
      drawdown   = [[3.1 * 0.8 / 100.0, 0.015].max, 0.060].min
      distance   = [[drawdown * 1.1, 0.030].max, 0.12].min
      lock       = [[14.2 * 0.20 / 100.0, 0.06].max, 0.15].min
      trail      = [[1.0 - (3.1 * 0.8 / 100.0), 0.55].max, 0.92].min
      early      = [[activation * 0.85, 0.020].max, 0.06].min
      breakeven  = [[activation * 1.5, 0.040].max, 0.12].min
      act_trig   = [[target * 0.55, 0.08].max, 0.20].min

      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          percentage_pnl_exit: { target_pct: target },
          trailing: { activation_pct: activation, drawdown_pct: drawdown },
          profit_floor: { lock_pct: lock, trail_pct: trail },
          institutional_trailing: {
            nifty: {
              trailing_distance: distance, early_trigger: early,
              breakeven_trigger: breakeven, activation_trigger: act_trig
            }
          }
        }
      })

      patch = described_class.build(combined_stats: combined_stats, symbol: 'NIFTY')
      expect(patch).to eq({})
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/options/calibration_config_patch_builder_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::CalibrationConfigPatchBuilder`

- [ ] **Step 3: Write the service**

```ruby
# app/services/options/calibration_config_patch_builder.rb
# frozen_string_literal: true

module Options
  # Derives algo.yml-compatible config overrides from weighted calibration stats.
  #
  # Input stats are in percentage POINTS (e.g. avg_gain: 14.2 means 14.2%).
  # Formulas divide by 100 to produce decimal config values (e.g. 0.064).
  #
  # Only emits keys where the proposed value differs from the current active
  # config by ≥10%, to avoid noisy patches that change nothing meaningful.
  #
  # Returns a string-keyed Hash safe for deep_merge into algo_config_overrides.
  # adaptive_drawdown is deliberately excluded — it is an array-of-hashes
  # that cannot be safely deep-merged with plain Hash#deep_merge.
  class CalibrationConfigPatchBuilder
    CHANGE_THRESHOLD = 0.10  # 10% minimum change to include a key

    def self.build(combined_stats:, symbol:)
      new(combined_stats: combined_stats, symbol: symbol).build
    end

    def initialize(combined_stats:, symbol:)
      @stats  = combined_stats
      @symbol = symbol.to_s.downcase
    end

    def build
      current = AlgoConfig.fetch
      proposed = derive_values
      filter_significant_changes(proposed, current).deep_stringify_keys
    end

    private

    def derive_values
      avg_gain        = @stats[:avg_gain].to_f
      avg_retrace_abs = @stats[:avg_retrace_abs].to_f

      target_pct     = clamp(avg_gain * 0.45 / 100.0, 0.08, 0.35)
      activation_pct = clamp(avg_gain * 0.25 / 100.0, 0.020, 0.08)
      drawdown_pct   = clamp(avg_retrace_abs * 0.80 / 100.0, 0.015, 0.060)
      distance       = clamp(drawdown_pct * 1.1, 0.030, 0.12)
      lock_pct       = clamp(avg_gain * 0.20 / 100.0, 0.06, 0.15)
      trail_pct      = clamp(1.0 - (avg_retrace_abs * 0.80 / 100.0), 0.55, 0.92)
      early_trigger  = clamp(activation_pct * 0.85, 0.020, 0.06)
      breakeven      = clamp(activation_pct * 1.5, 0.040, 0.12)
      activation_it  = clamp(target_pct * 0.55, 0.08, 0.20)

      {
        risk: {
          percentage_pnl_exit: { target_pct: target_pct },
          trailing: { activation_pct: activation_pct, drawdown_pct: drawdown_pct },
          profit_floor: { lock_pct: lock_pct, trail_pct: trail_pct },
          institutional_trailing: {
            @symbol.to_sym => {
              trailing_distance: distance,
              early_trigger:     early_trigger,
              breakeven_trigger: breakeven,
              activation_trigger: activation_it
            }
          }
        }
      }
    end

    # Recursively walks proposed and current; returns only paths where
    # proposed leaf differs from current leaf by ≥ CHANGE_THRESHOLD (10%).
    def filter_significant_changes(proposed, current, path = [])
      result = {}
      proposed.each do |key, value|
        current_value = current.is_a?(Hash) ? (current[key] || current[key.to_s]) : nil

        if value.is_a?(Hash)
          sub = filter_significant_changes(value, current_value || {}, path + [key])
          result[key] = sub unless sub.empty?
        elsif significant_change?(value, current_value)
          result[key] = value.round(4)
        end
      end
      result
    end

    def significant_change?(proposed_val, current_val)
      return true if current_val.nil? || current_val.to_f.zero?

      deviation = (proposed_val.to_f - current_val.to_f).abs / current_val.to_f
      deviation >= CHANGE_THRESHOLD
    end

    def clamp(value, min, max)
      [[value, min].max, max].min.round(4)
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/options/calibration_config_patch_builder_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/options/calibration_config_patch_builder.rb \
        spec/services/options/calibration_config_patch_builder_spec.rb
git commit -m "feat: add Options::CalibrationConfigPatchBuilder"
```

---

## Chunk 4: Orchestration

### Task 7: `Options::AutoCalibrator`

**Files:**
- Create: `app/services/options/auto_calibrator.rb`
- Test: `spec/services/options/auto_calibrator_spec.rb`

**Background:** Orchestrates the full calibration pipeline. Never raises — all errors are rescued and return nil or partial results. Fetches OHLCV data from `DhanHQ::Models::ExpiredOptionsData` for strikes `'ATM'`, `'ATM+1'`, `'ATM-1'` per expiry window. Transforms raw OHLCV into `HistoricalCalibrationEngine`-compatible rows (string-keyed, one row per expiry cycle). Runs the engine three times. Delegates combining, regime detection, and patch building to the other services.

**Key row format** (matches `HistoricalCalibrationEngine`'s `series("#{prefix}_#{stat}")` reads):
```
ce_max_gain_pct  = cycle_stats[:max_gain_pct]   for CE fetch
ce_max_loss_pct  = cycle_stats[:max_loss_pct]   for CE
ce_retrace       = cycle_stats[:post_peak_retrace]
ce_oc_pct        = cycle_stats[:open_to_close_pct]
ce_entry         = cycle_stats[:entry]
ce_corr_slope    = correlation_slope(ce_candles) or 0.0
ce_morning_oc    = session_breakdown['Morning'][:oc_pct] or 0.0
ce_midday_oc     = session_breakdown['Midday'][:oc_pct]  or 0.0
ce_afternoon_oc  = session_breakdown['Afternoon'][:oc_pct] or 0.0
(pe_ prefix for PUT leg)
```

- [ ] **Step 1: Write failing tests with WebMock stubs**

```ruby
# spec/services/options/auto_calibrator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::AutoCalibrator do
  let(:symbol) { 'NIFTY' }

  # Minimal fake ExpiredOptionsData response
  def fake_dhan_result(candle_count: 5)
    ts_base = Time.new(2026, 3, 10, 9, 15, 0, '+05:30').to_i
    timestamps = candle_count.times.map { |i| ts_base + (i * 300) } # 5-min bars

    data_hash = {
      'timestamp' => timestamps,
      'open'      => [100.0] * candle_count,
      'high'      => [120.0] * candle_count,
      'low'       => [90.0]  * candle_count,
      'close'     => [105.0] * candle_count,
      'volume'    => [1000]  * candle_count,
      'oi'        => [5000]  * candle_count,
      'spot'      => [22000.0] * candle_count,
      'strike'    => [22000.0] * candle_count
    }

    result = instance_double('DhanHQ::Models::ExpiredOptionsData')
    allow(result).to receive(:data).and_return({ 'ce' => data_hash, 'pe' => data_hash })
    result
  end

  before do
    # Stub all DhanHQ fetches to return fake data
    allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(fake_dhan_result)

    # Stub IndexConfigLoader
    allow(IndexConfigLoader).to receive(:load_indices).and_return([
      { key: 'NIFTY', segment: 'NSE_FNO', sid: '13' }
    ])
  end

  describe '.call' do
    it 'returns a CalibrationRun record on success' do
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_a(CalibrationRun)
      expect(result).to be_persisted
    end

    it 'persists the CalibrationRun with the correct symbol' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.symbol).to eq('NIFTY')
    end

    it 'stores non-empty raw_stats' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.raw_stats).not_to be_empty
    end

    it 'stores proposed_patch (may be empty hash if nothing changed >10%)' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.proposed_patch).to be_a(Hash)
    end

    it 'returns nil when DhanHQ returns nil for all strikes' do
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(nil)
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_nil
    end

    it 'returns nil when IndexConfigLoader cannot find the symbol' do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_nil
    end

    it 'still returns a result when OTM1 fetch fails (ATM-only fallback)' do
      call_count = 0
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch) do
        call_count += 1
        call_count == 1 ? fake_dhan_result : nil  # ATM succeeds, rest fail
      end
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).not_to be_nil
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/options/auto_calibrator_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::AutoCalibrator`

- [ ] **Step 3: Write the service**

```ruby
# app/services/options/auto_calibrator.rb
# frozen_string_literal: true

module Options
  # Automated calibration orchestrator.
  #
  # Never raises. All DhanHQ fetches are individually rescued.
  # Returns a persisted CalibrationRun on success, nil if all fetches fail.
  #
  # Usage:
  #   run = Options::AutoCalibrator.call(symbol: 'NIFTY', weeks: 52)
  #   run&.propose_config!
  class AutoCalibrator
    SESSIONS = {
      'Morning'   => ((9 * 60) + 15)..(11 * 60),
      'Midday'    => ((11 * 60) + 1)..(13 * 60),
      'Afternoon' => ((13 * 60) + 1)..((15 * 60) + 30)
    }.freeze

    STRIKES = %w[ATM ATM+1 ATM-1].freeze

    def self.call(symbol:, weeks: 52)
      new(symbol: symbol, weeks: weeks).call
    end

    def initialize(symbol:, weeks:)
      @symbol = symbol.to_s.upcase
      @weeks  = weeks
    end

    def call
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @symbol }
      unless index_cfg
        Rails.logger.warn("[AutoCalibrator] #{@symbol}: not found in IndexConfigLoader")
        return nil
      end

      @security_id = index_cfg[:sid].to_s
      @segment     = @symbol == 'SENSEX' ? 'BSE_FNO' : 'NSE_FNO'

      windows = Options::ExpiryCalendar.windows(symbol: @symbol, weeks: @weeks)

      atm_result  = run_engine_for_strike('ATM', windows)
      otm1_result = run_engine_for_strike('ATM+1', windows)
      otm2_result = run_engine_for_strike('ATM-1', windows)

      if atm_result.nil?
        Rails.logger.error("[AutoCalibrator] #{@symbol}: all ATM fetches failed — aborting")
        return nil
      end

      combined_stats = Options::StrikeAggregator.combine(
        atm_stats:  { ce: atm_result[:ce],  pe: atm_result[:pe] },
        otm1_stats: otm1_result ? { ce: otm1_result[:ce], pe: otm1_result[:pe] } : nil,
        otm2_stats: otm2_result ? { ce: otm2_result[:ce], pe: otm2_result[:pe] } : nil
      )

      regime      = Options::RegimeDetector.check(symbol: @symbol, combined_stats: combined_stats)
      patch       = Options::CalibrationConfigPatchBuilder.build(
        combined_stats: combined_stats, symbol: @symbol
      )

      strike_mode = (otm1_result || otm2_result) ? 'atm_plus_minus' : 'atm_only'

      run = CalibrationRun.create!(
        symbol:          @symbol,
        weeks_analyzed:  @weeks,
        strike_mode:     strike_mode,
        raw_stats:       combined_stats,
        proposed_patch:  patch,
        is_regime_shift: regime[:shift],
        regime_reason:   regime[:reason]
      )

      run
    rescue StandardError => e
      Rails.logger.error("[AutoCalibrator] #{@symbol} unexpected error: #{e.class} — #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    private

    # Fetches OHLCV data for all windows for a given strike, builds
    # HistoricalCalibrationEngine-compatible rows, and runs the engine.
    # Returns engine result hash, or nil if no data could be fetched.
    def run_engine_for_strike(strike_code, windows)
      rows = build_rows_for_strike(strike_code, windows)
      return nil if rows.empty?

      Options::HistoricalCalibrationEngine.new(
        rows: rows, symbol: @symbol
      ).call
    rescue StandardError => e
      Rails.logger.warn("[AutoCalibrator] #{@symbol} #{strike_code} engine error: #{e.class} — #{e.message}")
      nil
    end

    def build_rows_for_strike(strike_code, windows)
      windows.filter_map do |window|
        ce_candles = fetch_candles(strike_code, window, 'CALL')
        pe_candles = fetch_candles(strike_code, window, 'PUT')
        next nil if ce_candles.empty? && pe_candles.empty?

        build_row(ce_candles, pe_candles)
      end
    end

    def fetch_candles(strike_code, window, opt_type)
      side = opt_type == 'CALL' ? 'ce' : 'pe'
      raw = DhanHQ::Models::ExpiredOptionsData.fetch(
        exchange_segment: @segment,
        interval: '5',
        security_id: @security_id,
        instrument: 'OPTIDX',
        expiry_flag: 'WEEK',
        expiry_code: 1,
        strike: strike_code,
        drv_option_type: opt_type,
        required_data: %w[open high low close volume oi spot strike],
        from_date: window[:from].strftime('%Y-%m-%d'),
        to_date:   window[:to].strftime('%Y-%m-%d')
      )
      d = raw&.data&.dig(side)
      return [] unless d&.dig('timestamp')

      d['timestamp'].map.with_index do |ts, i|
        t = Time.at(ts).in_time_zone('Asia/Kolkata')
        {
          time: t.iso8601, day: t.wday,
          mins: (t.hour * 60) + t.min,
          open: d['open'][i].to_f, high: d['high'][i].to_f,
          low:  d['low'][i].to_f,  close: d['close'][i].to_f,
          volume: d['volume'][i].to_i, oi: d['oi'][i].to_i,
          spot: d['spot'][i].to_f, strike: d['strike'][i].to_f
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[AutoCalibrator] #{@symbol} fetch_candles #{strike_code} #{opt_type}: #{e.message}")
      []
    end

    def build_row(ce_candles, pe_candles)
      ce_stats = ce_candles.any? ? cycle_stats(ce_candles) : nil
      pe_stats = pe_candles.any? ? cycle_stats(pe_candles) : nil
      return nil unless ce_stats || pe_stats

      ce_sess = ce_candles.any? ? session_breakdown(ce_candles) : {}
      pe_sess = pe_candles.any? ? session_breakdown(pe_candles) : {}
      ce_corr = ce_candles.any? ? correlation_slope(ce_candles).to_f : 0.0
      pe_corr = pe_candles.any? ? correlation_slope(pe_candles).to_f : 0.0

      {
        'symbol'         => @symbol,
        'ce_max_gain_pct'  => ce_stats&.dig(:max_gain_pct).to_f,
        'ce_max_loss_pct'  => ce_stats&.dig(:max_loss_pct).to_f,
        'ce_retrace'       => ce_stats&.dig(:post_peak_retrace).to_f,
        'ce_oc_pct'        => ce_stats&.dig(:open_to_close_pct).to_f,
        'ce_entry'         => ce_stats&.dig(:entry).to_f,
        'ce_corr_slope'    => ce_corr,
        'ce_morning_oc'    => ce_sess.dig('Morning', :oc_pct).to_f,
        'ce_midday_oc'     => ce_sess.dig('Midday', :oc_pct).to_f,
        'ce_afternoon_oc'  => ce_sess.dig('Afternoon', :oc_pct).to_f,
        'pe_max_gain_pct'  => pe_stats&.dig(:max_gain_pct).to_f,
        'pe_max_loss_pct'  => pe_stats&.dig(:max_loss_pct).to_f,
        'pe_retrace'       => pe_stats&.dig(:post_peak_retrace).to_f,
        'pe_oc_pct'        => pe_stats&.dig(:open_to_close_pct).to_f,
        'pe_entry'         => pe_stats&.dig(:entry).to_f,
        'pe_corr_slope'    => pe_corr,
        'pe_morning_oc'    => pe_sess.dig('Morning', :oc_pct).to_f,
        'pe_midday_oc'     => pe_sess.dig('Midday', :oc_pct).to_f,
        'pe_afternoon_oc'  => pe_sess.dig('Afternoon', :oc_pct).to_f
      }
    end

    def cycle_stats(candles)
      entry   = candles.first[:open].to_f
      max_h   = candles.map { |c| c[:high] }.max.to_f
      min_l   = candles.map { |c| c[:low] }.min.to_f
      final_c = candles.last[:close].to_f
      peak_idx    = candles.index { |c| c[:high] == max_h } || 0
      pullback_l  = candles[peak_idx..].map { |c| c[:low] }.min.to_f

      {
        entry:              entry.round(2),
        max_gain_pct:       pct(max_h, entry),
        max_loss_pct:       pct(min_l, entry),
        open_to_close_pct:  pct(final_c, entry),
        post_peak_retrace:  pct(pullback_l, max_h).round(2)
      }
    end

    def session_breakdown(candles)
      SESSIONS.transform_values do |range|
        sess = candles.select { |c| range.cover?(c[:mins]) }
        next nil if sess.empty?

        s_open  = sess.first[:open].to_f
        s_close = sess.last[:close].to_f
        { oc_pct: pct(s_close, s_open) }
      end
    end

    def correlation_slope(candles)
      return 0.0 if candles.empty?

      base_spot   = candles.first[:spot].to_f
      base_option = candles.first[:open].to_f
      return 0.0 if base_spot.zero? || base_option.zero?

      pairs = candles.map { |c| [pct(c[:spot].to_f, base_spot), pct(c[:close].to_f, base_option)] }
      n     = pairs.size.to_f
      sx    = pairs.sum { |x, _| x }
      sy    = pairs.sum { |_, y| y }
      sx2   = pairs.sum { |x, _| x**2 }
      sxy   = pairs.sum { |x, y| x * y }
      denom = (n * sx2) - (sx**2)
      return 0.0 if denom.zero?

      (((n * sxy) - (sx * sy)) / denom).round(2)
    end

    def pct(v, base)
      base.zero? ? 0.0 : ((v - base) / base.to_f * 100).round(2)
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/options/auto_calibrator_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Run full spec suite for regressions**

```bash
bundle exec rspec spec/services/options/ -f d
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/options/auto_calibrator.rb \
        spec/services/options/auto_calibrator_spec.rb
git commit -m "feat: add Options::AutoCalibrator orchestrator"
```

---

### Task 8: `Options::CalibrationNotifier`

**Files:**
- Create: `app/services/options/calibration_notifier.rb`
- Test: `spec/services/options/calibration_notifier_spec.rb`

**Background:** Sends Telegram notifications via the existing `Notifications::Telegram::Client` (already used elsewhere in the app). Formats a brief summary showing the symbol, proposed config values, and regime shift flag. Send failure is rescued and logged — it must not propagate to the job.

- [ ] **Step 1: Check the existing Telegram client**

```bash
ls app/services/notifications/telegram/
```

Confirm `client.rb` exists there and note the `.send_message` or equivalent public method. Then write the notifier using that pattern.

- [ ] **Step 2: Write failing tests**

```ruby
# spec/services/options/calibration_notifier_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationNotifier do
  let(:run) do
    CalibrationRun.create!(
      symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 },
      proposed_patch: { 'risk' => { 'percentage_pnl_exit' => { 'target_pct' => 0.064 } } },
      is_regime_shift: false
    )
  end

  let(:telegram_client) { instance_double(Notifications::Telegram::Client, send_message: true) }

  before do
    allow(Notifications::Telegram::Client).to receive(:instance).and_return(telegram_client)
  end

  describe '.notify' do
    it 'sends a Telegram message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message).once
    end

    it 'includes symbol in the message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message).with(a_string_including('NIFTY'))
    end

    it 'does not raise when Telegram fails' do
      allow(telegram_client).to receive(:send_message).and_raise(StandardError, 'network error')
      expect { described_class.notify('NIFTY', run) }.not_to raise_error
    end
  end

  describe '.notify_error' do
    it 'sends an error notification without raising' do
      expect { described_class.notify_error('NIFTY', StandardError.new('oops')) }.not_to raise_error
    end
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bundle exec rspec spec/services/options/calibration_notifier_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Options::CalibrationNotifier`

- [ ] **Step 4: Write the service**

Look at how other notifiers send messages (e.g. `app/services/notifications/telegram/`). Use the same `Notifications::Telegram::Client.instance.send_message(text)` pattern. Format the message to include:
- `📊 Calibration ready: #{symbol}` heading
- `Weeks: #{run.weeks_analyzed} | Strike mode: #{run.strike_mode}`
- If `run.is_regime_shift`: `⚠️ Regime shift: #{run.regime_reason}`
- Proposed patch keys (show only changed keys with proposed values)
- `Apply via Settings UI or POST /api/calibration_runs/#{run.id}/apply`

```ruby
# app/services/options/calibration_notifier.rb
# frozen_string_literal: true

module Options
  # Sends Telegram notifications for calibration events.
  # Failures are silently rescued — never propagate to the job.
  class CalibrationNotifier
    def self.notify(symbol, run)
      new.notify(symbol, run)
    end

    def self.notify_error(symbol, error)
      new.notify_error(symbol, error)
    end

    def notify(symbol, run)
      text = build_success_message(symbol, run)
      Notifications::Telegram::Client.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] Telegram send failed: #{e.class} — #{e.message}")
    end

    def notify_error(symbol, error)
      text = "❌ Calibration failed: #{symbol}\n#{error.class}: #{error.message}"
      Notifications::Telegram::Client.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] notify_error send failed: #{e.class} — #{e.message}")
    end

    private

    def build_success_message(symbol, run)
      lines = ["📊 *Calibration ready:* #{symbol}"]
      lines << "Weeks: #{run.weeks_analyzed} | Mode: #{run.strike_mode}"
      lines << "⚠️ *Regime shift:* #{run.regime_reason}" if run.is_regime_shift

      patch = run.proposed_patch
      if patch.empty?
        lines << "_No significant config changes (\<10% deviation from current)_"
      else
        lines << "*Proposed changes:*"
        flat_patch(patch).each { |k, v| lines << "  #{k}: #{v}" }
      end

      lines << "Apply: POST /api/calibration_runs/#{run.id}/apply"
      lines.join("\n")
    end

    # Flattens nested hash to dot-notation keys for display
    def flat_patch(hash, prefix = nil)
      hash.flat_map do |k, v|
        full_key = prefix ? "#{prefix}.#{k}" : k.to_s
        v.is_a?(Hash) ? flat_patch(v, full_key) : [[full_key, v]]
      end
    end
  end
end
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/options/calibration_notifier_spec.rb -f d
```

Expected: All examples pass (adjust Telegram client stub to match actual class name if needed).

- [ ] **Step 6: Commit**

```bash
git add app/services/options/calibration_notifier.rb \
        spec/services/options/calibration_notifier_spec.rb
git commit -m "feat: add Options::CalibrationNotifier"
```

---

### Task 9: `WeeklyCalibrationJob` + `recurring.yml`

**Files:**
- Create: `app/jobs/weekly_calibration_job.rb`
- Modify: `config/recurring.yml`
- Test: `spec/jobs/weekly_calibration_job_spec.rb`

**Background:** Solid Queue job. Positional args (`symbol = nil, weeks = 52`) — NOT keyword args (Ruby 3.3 Active Job serialisation raises `ArgumentError` on keyword-only signatures). When `symbol` is nil, runs both NIFTY and SENSEX. Each symbol is independently rescued so one failure doesn't block the other.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/jobs/weekly_calibration_job_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeeklyCalibrationJob do
  let(:mock_run) do
    instance_double(CalibrationRun, propose_config!: nil)
  end

  before do
    allow(Options::AutoCalibrator).to receive(:call).and_return(mock_run)
    allow(Options::CalibrationNotifier).to receive(:notify)
    allow(Options::CalibrationNotifier).to receive(:notify_error)
  end

  describe '#perform' do
    context 'with a specific symbol' do
      it 'runs AutoCalibrator for that symbol only' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52).once
        expect(Options::AutoCalibrator).not_to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end

      it 'calls propose_config! on the returned run' do
        described_class.new.perform('NIFTY', 52)
        expect(mock_run).to have_received(:propose_config!)
      end

      it 'notifies via CalibrationNotifier' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::CalibrationNotifier).to have_received(:notify).with('NIFTY', mock_run)
      end
    end

    context 'with nil symbol (both indices)' do
      it 'runs AutoCalibrator for NIFTY and SENSEX' do
        described_class.new.perform
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52)
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end
    end

    context 'when AutoCalibrator returns nil (all fetches failed)' do
      before { allow(Options::AutoCalibrator).to receive(:call).and_return(nil) }

      it 'calls notify_error' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::CalibrationNotifier).to have_received(:notify_error)
      end

      it 'does not raise' do
        expect { described_class.new.perform('NIFTY', 52) }.not_to raise_error
      end
    end

    context 'when NIFTY raises an exception' do
      before do
        call_count = 0
        allow(Options::AutoCalibrator).to receive(:call) do |symbol:, **|
          call_count += 1
          raise StandardError, 'NIFTY exploded' if symbol == 'NIFTY'
          mock_run
        end
      end

      it 'still runs SENSEX' do
        described_class.new.perform  # nil symbol → both
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end

      it 'calls notify_error for NIFTY' do
        described_class.new.perform
        expect(Options::CalibrationNotifier).to have_received(:notify_error).with('NIFTY', anything)
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/jobs/weekly_calibration_job_spec.rb -f d
```

Expected: FAIL — `uninitialized constant WeeklyCalibrationJob`

- [ ] **Step 3: Write the job**

```ruby
# app/jobs/weekly_calibration_job.rb
# frozen_string_literal: true

# Solid Queue weekly job for automated options calibration.
# Runs every Sunday at 6:00 AM IST in production.
#
# Positional defaults (not keyword args) — Ruby 3.3 Active Job
# serialisation raises ArgumentError on keyword-only signatures.
#
# Usage:
#   WeeklyCalibrationJob.perform_later           # both symbols (scheduled)
#   WeeklyCalibrationJob.perform_later('NIFTY')  # manual single-symbol run
class WeeklyCalibrationJob < ApplicationJob
  queue_as :background

  def perform(symbol = nil, weeks = 52)
    symbols = symbol ? [symbol.to_s.upcase] : %w[NIFTY SENSEX]

    symbols.each do |sym|
      run = Options::AutoCalibrator.call(symbol: sym, weeks: weeks)
      if run
        run.propose_config!
        Options::CalibrationNotifier.notify(sym, run)
      else
        Options::CalibrationNotifier.notify_error(sym, RuntimeError.new('AutoCalibrator returned nil — all DhanHQ fetches failed'))
      end
    rescue StandardError => e
      Rails.logger.error("[WeeklyCalibrationJob] #{sym} failed: #{e.class} — #{e.message}")
      Options::CalibrationNotifier.notify_error(sym, e)
    end
  end
end
```

- [ ] **Step 4: Add recurring schedule (production only)**

Open `config/recurring.yml` and add under the `production:` key:

```yaml
  weekly_options_calibration:
    class: WeeklyCalibrationJob
    schedule: every Sunday at 6:00 am Asia/Kolkata
    queue_name: background
    priority: 3
    description: "Weekly ATM±1 options calibration — generates config patch proposal for NIFTY and SENSEX"
```

- [ ] **Step 5: Reload recurring schedule**

```bash
rails solid_queue:load_recurring
```

Expected: No errors. If running in development, the entry won't appear (production-only). Confirm `recurring.yml` is valid YAML:

```bash
ruby -e "require 'yaml'; YAML.load_file('config/recurring.yml'); puts 'OK'"
```

- [ ] **Step 6: Run job tests**

```bash
bundle exec rspec spec/jobs/weekly_calibration_job_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/weekly_calibration_job.rb \
        config/recurring.yml \
        spec/jobs/weekly_calibration_job_spec.rb
git commit -m "feat: add WeeklyCalibrationJob and recurring schedule"
```

---

## Chunk 5: API

### Task 10: `Api::CalibrationRunsController` + routes

**Files:**
- Create: `app/controllers/api/calibration_runs_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/calibration_runs_spec.rb`

**Background:** Three actions: `index` (last 10 runs per query, includes `current_snapshot`), `show`, `apply` (POST to `/apply` sub-resource). `current_snapshot` is a single `AlgoConfig.fetch` call per request extracting all 9 patch-builder-emittable keys. The `apply` action returns 422 on double-apply (idempotency).

- [ ] **Step 1: Add routes**

In `config/routes.rb`, inside the `namespace :api` block, add:

```ruby
resources :calibration_runs, only: %i[index show] do
  member do
    post :apply
  end
end
```

- [ ] **Step 2: Write failing request specs**

```ruby
# spec/requests/api/calibration_runs_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::CalibrationRuns', type: :request do
  def create_run(symbol: 'NIFTY', applied_at: nil)
    CalibrationRun.create!(
      symbol: symbol, weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2 },
      proposed_patch: { 'risk' => { 'percentage_pnl_exit' => { 'target_pct' => 0.064 } } },
      applied_at: applied_at
    )
  end

  describe 'GET /api/calibration_runs' do
    before { create_run }

    it 'returns 200 with an array of runs' do
      get '/api/calibration_runs'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.size).to be >= 1
    end

    it 'includes current_snapshot in each run' do
      get '/api/calibration_runs'
      json = JSON.parse(response.body)
      expect(json.first).to have_key('current_snapshot')
    end

    it 'respects limit param' do
      5.times { create_run }
      get '/api/calibration_runs', params: { limit: 3 }
      json = JSON.parse(response.body)
      expect(json.size).to be <= 3
    end
  end

  describe 'GET /api/calibration_runs/:id' do
    let(:run) { create_run }

    it 'returns 200 with the run' do
      get "/api/calibration_runs/#{run.id}"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['id']).to eq(run.id)
    end

    it 'returns 404 for unknown id' do
      get '/api/calibration_runs/999999'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/calibration_runs/:id/apply' do
    let(:run) { create_run }

    before do
      allow(Setting).to receive(:put)
      allow(Setting).to receive(:find_by).and_return(nil)
      allow(AlgoConfig).to receive(:reset!)
    end

    it 'returns 200 on success' do
      post "/api/calibration_runs/#{run.id}/apply"
      expect(response).to have_http_status(:ok)
    end

    it 'returns applied_at in the response' do
      post "/api/calibration_runs/#{run.id}/apply"
      json = JSON.parse(response.body)
      expect(json['applied_at']).to be_present
    end

    it 'returns 422 on double-apply' do
      run.update!(applied_at: Time.current)
      post "/api/calibration_runs/#{run.id}/apply"
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 for unknown id' do
      post '/api/calibration_runs/999999/apply'
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bundle exec rspec spec/requests/api/calibration_runs_spec.rb -f d
```

Expected: FAIL — routing errors or controller not found.

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/api/calibration_runs_controller.rb
# frozen_string_literal: true

module Api
  class CalibrationRunsController < ApplicationController
    # GET /api/calibration_runs
    # Returns last N runs ordered by created_at desc, with current_snapshot.
    def index
      limit = (params[:limit] || 10).to_i.clamp(1, 50)
      runs  = CalibrationRun.order(created_at: :desc).limit(limit).to_a
      snap  = current_config_snapshot

      render json: runs.map { |r| r.as_json.merge('current_snapshot' => snap) }
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] index error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # GET /api/calibration_runs/:id
    def show
      run = CalibrationRun.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless run

      render json: run.as_json.merge('current_snapshot' => current_config_snapshot)
    rescue StandardError => e
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # POST /api/calibration_runs/:id/apply
    def apply
      run = CalibrationRun.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless run

      run.apply!(applied_by: 'api')
      render json: run.as_json
    rescue RuntimeError => e
      # apply! raises RuntimeError('already applied') for double-apply
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[CalibrationRunsController] apply error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    private

    # Single AlgoConfig.fetch per request; extracts all keys that
    # CalibrationConfigPatchBuilder may emit so frontend can compute diff.
    def current_config_snapshot
      cfg = AlgoConfig.fetch
      {
        'risk.percentage_pnl_exit.target_pct'       => cfg.dig(:risk, :percentage_pnl_exit, :target_pct),
        'risk.trailing.activation_pct'              => cfg.dig(:risk, :trailing, :activation_pct),
        'risk.trailing.drawdown_pct'                => cfg.dig(:risk, :trailing, :drawdown_pct),
        'risk.profit_floor.lock_pct'                => cfg.dig(:risk, :profit_floor, :lock_pct),
        'risk.profit_floor.trail_pct'               => cfg.dig(:risk, :profit_floor, :trail_pct),
        'institutional_trailing.trailing_distance'  => cfg.dig(:risk, :institutional_trailing, :trailing_distance),
        'institutional_trailing.early_trigger'      => cfg.dig(:risk, :institutional_trailing, :early_trigger),
        'institutional_trailing.breakeven_trigger'  => cfg.dig(:risk, :institutional_trailing, :breakeven_trigger),
        'institutional_trailing.activation_trigger' => cfg.dig(:risk, :institutional_trailing, :activation_trigger)
      }
    rescue StandardError
      {}
    end
  end
end
```

- [ ] **Step 5: Run request specs**

```bash
bundle exec rspec spec/requests/api/calibration_runs_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 6: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/calibration_runs_controller.rb \
                    config/routes.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/calibration_runs_controller.rb \
        config/routes.rb \
        spec/requests/api/calibration_runs_spec.rb
git commit -m "feat: add CalibrationRunsController with index/show/apply endpoints"
```

---

## Chunk 6: Full Run Verification

### Task 11: End-to-end smoke test (manual)

**Purpose:** Verify the pipeline works end-to-end in development with a manual job trigger.

- [ ] **Step 1: Run the full RSpec suite for all new files**

```bash
bundle exec rspec spec/models/calibration_run_spec.rb \
                  spec/services/options/expiry_calendar_spec.rb \
                  spec/services/options/strike_aggregator_spec.rb \
                  spec/services/options/regime_detector_spec.rb \
                  spec/services/options/calibration_config_patch_builder_spec.rb \
                  spec/services/options/auto_calibrator_spec.rb \
                  spec/services/options/calibration_notifier_spec.rb \
                  spec/jobs/weekly_calibration_job_spec.rb \
                  spec/requests/api/calibration_runs_spec.rb \
                  -f d
```

Expected: All pass, 0 failures.

- [ ] **Step 2: Run RuboCop on all new files**

```bash
bundle exec rubocop \
  app/models/calibration_run.rb \
  app/services/options/expiry_calendar.rb \
  app/services/options/strike_aggregator.rb \
  app/services/options/regime_detector.rb \
  app/services/options/calibration_config_patch_builder.rb \
  app/services/options/auto_calibrator.rb \
  app/services/options/calibration_notifier.rb \
  app/jobs/weekly_calibration_job.rb \
  app/controllers/api/calibration_runs_controller.rb
```

Expected: No offenses (resolve any auto-correctable issues with `rubocop -A`).

- [ ] **Step 3: Smoke test in Rails console**

```bash
rails console
```

```ruby
# Verify CalibrationRun model
run = CalibrationRun.create!(
  symbol: 'NIFTY', weeks_analyzed: 1, strike_mode: 'atm_only',
  raw_stats: { 'avg_gain' => 14.0 },
  proposed_patch: { 'risk' => { 'trailing' => { 'drawdown_pct' => 0.025 } } }
)
puts run.persisted?  # => true

# Verify API route
puts Rails.application.routes.url_helpers.apply_api_calibration_run_path(run)
# => /api/calibration_runs/:id/apply

# Verify ExpiryCalendar
windows = Options::ExpiryCalendar.windows(symbol: 'NIFTY', weeks: 2)
puts windows.map { |w| "#{w[:expiry]} (#{w[:expiry].strftime('%A')})" }
# => should show two Thursdays
```

- [ ] **Step 4: Commit final smoke test notes (if any adjustments were made)**

```bash
git add -p  # stage only adjusted files
git commit -m "fix: address any smoke test issues"
```

---

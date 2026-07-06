# Chain Confirmation Entry Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new entry guard that confirms live OI/IV/delta on the already-picked strike before order placement, reading data from the already-running `Options::ChainWatchService` instances.

**Architecture:** A small `Options::ChainWatchRegistry` (index_key → running `ChainWatchService` instance) is populated at daemon boot; a new `Entries::Guards::ChainConfirmationGuard` reads from it and slots into the existing 32-guard `EntryGuardPipeline`, following the exact shape of the existing `IvVolGateGuard`.

**Tech Stack:** Ruby 3.3.4, Rails 8, RSpec.

## Global Constraints

- Never modify LOCKED files: `app/services/options/chain_analyzer.rb`, `app/services/options/derivative_chain_analyzer.rb`, `lib/trading_system/supervisor.rb` internals. Only call their existing public methods where relevant.
- `Options::ChainWatchService` itself is not modified — only read via its existing public `#snapshot` method.
- The new guard must fail-open (`PASS`) on any missing/stale data or error — matching `IvVolGateGuard`/`OptionVolumeVelocityGuard`'s existing convention. It must never crash the pipeline or become the reason a trade the other 31 guards approved gets blocked due to a data-availability hiccup.
- Guard must be inserted in `EntryGuardPipeline`'s handler array immediately after `Guards::OptionVolumeVelocityGuard` and before `Guards::EarliestEntryGuard`.
- Config lives under `risk.chain_confirmation_gate` in `config/algo.yml`, following the exact structure of the neighboring `iv_vol_gate`/`volume_velocity_gate` blocks (config/algo.yml:378-388).

---

### Task 1: `Options::ChainWatchRegistry`

**Files:**
- Create: `app/services/options/chain_watch_registry.rb`
- Test: `spec/services/options/chain_watch_registry_spec.rb`

**Interfaces:**
- Consumes: any object responding to `#snapshot` (in practice, `Options::ChainWatchService` instances, but the registry itself doesn't need to know that — it just stores and returns whatever was registered).
- Produces: `Options::ChainWatchRegistry.register(index_key, service)` (class method, stores `service` keyed by `index_key.to_s.upcase`) and `Options::ChainWatchRegistry.snapshot_for(index_key)` (class method, returns `registered_service.snapshot` or `nil` if no service is registered for that key). Task 2 calls `.register`; Task 3's guard calls `.snapshot_for`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/options/chain_watch_registry_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainWatchRegistry do
  after { described_class.reset! }

  describe '.register and .snapshot_for' do
    it 'returns the registered service\'s snapshot, keyed case-insensitively' do
      service = instance_double(Options::ChainWatchService, snapshot: { index_key: 'NIFTY', spot: 24800.0 })

      described_class.register('nifty', service)

      expect(described_class.snapshot_for('NIFTY')).to eq({ index_key: 'NIFTY', spot: 24800.0 })
      expect(described_class.snapshot_for('nifty')).to eq({ index_key: 'NIFTY', spot: 24800.0 })
    end

    it 'returns nil for an index that was never registered' do
      expect(described_class.snapshot_for('BANKNIFTY')).to be_nil
    end

    it 'returns nil if the registered service raises when snapshotting' do
      service = instance_double(Options::ChainWatchService)
      allow(service).to receive(:snapshot).and_raise(StandardError, 'boom')

      described_class.register('SENSEX', service)

      expect(described_class.snapshot_for('SENSEX')).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/options/chain_watch_registry_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant Options::ChainWatchRegistry`

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/options/chain_watch_registry.rb
# frozen_string_literal: true

module Options
  # In-process registry pointing at the already-running per-index
  # Options::ChainWatchService instances (one per NIFTY/BANKNIFTY/SENSEX,
  # created once at daemon boot in lib/trading_system/bootstrap.rb).
  #
  # Exists so consumers that need live chain data (e.g. entry guards) can
  # reach the running instance's current snapshot without constructing a
  # fresh, unstarted ChainWatchService of their own.
  class ChainWatchRegistry
    @services = {}
    @mutex = Mutex.new

    class << self
      def register(index_key, service)
        @mutex.synchronize { @services[index_key.to_s.upcase] = service }
      end

      def snapshot_for(index_key)
        service = @mutex.synchronize { @services[index_key.to_s.upcase] }
        return nil unless service

        service.snapshot
      rescue StandardError => e
        Rails.logger.warn("[ChainWatchRegistry] snapshot_for(#{index_key}) failed: #{e.class} - #{e.message}")
        nil
      end

      # Test-only: clears registered services between examples.
      def reset!
        @mutex.synchronize { @services = {} }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/options/chain_watch_registry_spec.rb -v`
Expected: PASS (3 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/options/chain_watch_registry.rb spec/services/options/chain_watch_registry_spec.rb
git commit -m "feat: add Options::ChainWatchRegistry for cross-consumer chain-snapshot access"
```

---

### Task 2: Wire the registry into daemon boot

**Files:**
- Modify: `lib/trading_system/bootstrap.rb:96-100` (the existing `register_chain_watch` private method)
- Modify: `spec/lib/trading_system/bootstrap_spec.rb`

**Interfaces:**
- Consumes: Task 1's `Options::ChainWatchRegistry.register(index_key, service)`.
- Produces: after `build_supervisor` runs, `Options::ChainWatchRegistry.snapshot_for('NIFTY')` (etc.) returns live data once the corresponding service starts — this is what Task 4's guard reads.

- [ ] **Step 1: Write the failing test**

```ruby
# Add to spec/lib/trading_system/bootstrap_spec.rb, inside the existing
# `describe '.build_supervisor'` block (which already has a `before` stubbing
# IndexConfigLoader — reuse it):

    it 'registers each ChainWatchService instance in Options::ChainWatchRegistry' do
      described_class.build_supervisor

      expect(Options::ChainWatchRegistry.snapshot_for('NIFTY')).not_to be_nil
      expect(Options::ChainWatchRegistry.snapshot_for('BANKNIFTY')).not_to be_nil
      expect(Options::ChainWatchRegistry.snapshot_for('SENSEX')).not_to be_nil
    ensure
      Options::ChainWatchRegistry.reset!
    end

    context 'when one index is disabled/unknown and ChainWatchService.new raises for it' do
      it 'does not register that index in the registry either' do
        original_new = Options::ChainWatchService.method(:new)
        allow(Options::ChainWatchService).to receive(:new) do |index_key:|
          raise "unknown_index:#{index_key}" if index_key == 'BANKNIFTY'

          original_new.call(index_key: index_key)
        end

        described_class.build_supervisor

        expect(Options::ChainWatchRegistry.snapshot_for('NIFTY')).not_to be_nil
        expect(Options::ChainWatchRegistry.snapshot_for('BANKNIFTY')).to be_nil
      ensure
        Options::ChainWatchRegistry.reset!
      end
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/trading_system/bootstrap_spec.rb -v`
Expected: FAIL — `Options::ChainWatchRegistry.snapshot_for('NIFTY')` returns `nil` (nothing registers it yet)

- [ ] **Step 3: Wire the registration**

```ruby
# In lib/trading_system/bootstrap.rb, replace the existing register_chain_watch method:

    def register_chain_watch(supervisor, key, index_key)
      service = Options::ChainWatchService.new(index_key: index_key)
      supervisor.register(key, service)
      Options::ChainWatchRegistry.register(index_key, service)
    rescue StandardError => e
      Rails.logger.warn("[Bootstrap] Skipping #{key} registration: #{e.class} - #{e.message}")
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/trading_system/bootstrap_spec.rb -v`
Expected: PASS (all examples, including the two new ones)

- [ ] **Step 5: Commit**

```bash
git add lib/trading_system/bootstrap.rb spec/lib/trading_system/bootstrap_spec.rb
git commit -m "feat: register ChainWatchService instances into ChainWatchRegistry at boot"
```

---

### Task 3: `Entries::Guards::ChainConfirmationGuard`

**Files:**
- Create: `app/services/entries/guards/chain_confirmation_guard.rb`
- Test: `spec/services/entries/guards/chain_confirmation_guard_spec.rb`

**Interfaces:**
- Consumes: Task 1's `Options::ChainWatchRegistry.snapshot_for(index_key)` → snapshot hash `{index_key:, spot:, atm_strike:, expiry:, legs: [{strike:, type:, security_id:, ltp:, oi:, oi_change:, iv:, delta:, ...}], chain_stale:, updated_at:}` or `nil`. `AlgoConfig.fetch.dig(:risk, :chain_confirmation_gate)` config hash. Guard pipeline context shape (established by existing sibling guards, e.g. `iv_vol_gate_guard_spec.rb`): `{index_cfg: {key: 'NIFTY'}, pick: {strike: 24800.0, type: 'CE', ...}, direction: :bullish}`.
- Produces: `Entries::Guards::ChainConfirmationGuard.call(context)` → `Entries::EntryGuardPipeline::PASS` or `{blocked: "<reason>"}` — this is what Task 4 wires into the pipeline's handler array.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/entries/guards/chain_confirmation_guard_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::ChainConfirmationGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { strike: 24800.0, type: 'CE', security_id: '24800CE' } }
  let(:context) { { index_cfg: index_cfg, pick: pick, direction: :bullish } }

  let(:default_config) do
    {
      risk: {
        chain_confirmation_gate: {
          enabled: true,
          min_oi_change: 0,
          min_iv: 8.0,
          max_iv: 45.0,
          min_delta: 0.25,
          max_delta: 0.75
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(default_config)
  end

  def stub_snapshot(legs)
    allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(
      { index_key: 'NIFTY', spot: 24800.0, atm_strike: 24800.0, chain_stale: false, legs: legs }
    )
  end

  describe '.call' do
    context 'when OI, IV, and delta are all within configured bands' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.5 }])
      end

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when OI change is below the minimum (no fresh buildup)' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: -200, iv: 15.0, delta: 0.5 }])
      end

      it 'blocks with an OI reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('OI change')
      end
    end

    context 'when IV is above the configured max' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 60.0, delta: 0.5 }])
      end

      it 'blocks with an IV reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('IV')
      end
    end

    context 'when delta is outside the configured band' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.9 }])
      end

      it 'blocks with a delta reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('delta')
      end
    end

    context 'when the guard is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { chain_confirmation_gate: { enabled: false } })
      end

      it 'passes without checking anything' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when no snapshot is registered for the index' do
      before { allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(nil) }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when the snapshot is stale' do
      before do
        allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(
          { chain_stale: true, legs: [{ strike: 24800.0, type: 'CE', oi_change: -999, iv: 99.0, delta: 0.99 }] }
        )
      end

      it 'fails open even though the leg data would otherwise block' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when no leg in the snapshot matches the picked strike/type' do
      before { stub_snapshot([{ strike: 25000.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.5 }]) }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when Options::ChainWatchRegistry raises' do
      before { allow(Options::ChainWatchRegistry).to receive(:snapshot_for).and_raise(StandardError, 'boom') }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entries/guards/chain_confirmation_guard_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant Entries::Guards::ChainConfirmationGuard`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/entries/guards/chain_confirmation_guard.rb
# frozen_string_literal: true

module Entries
  module Guards
    # Confirms the already-picked strike has live OI/IV/delta support before
    # entry: OI must be building (not flat/declining), IV must sit in a sane
    # band (not a blow-off extreme), and delta must sit in a sane band (not a
    # deep-ITM/far-OTM pick that slipped through strike selection).
    #
    # Reads from Options::ChainWatchRegistry, which points at the already-
    # running per-index Options::ChainWatchService instances — this guard
    # never constructs its own ChainWatchService.
    class ChainConfirmationGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        index_key = context[:index_cfg][:key].to_s.upcase
        snapshot = Options::ChainWatchRegistry.snapshot_for(index_key)
        return PASS if snapshot.nil? || snapshot[:chain_stale]

        pick = context[:pick]
        expected_type = context[:direction].to_s == 'bullish' ? 'CE' : 'PE'
        leg = snapshot[:legs].find { |l| l[:strike] == pick[:strike] && l[:type] == expected_type }
        return PASS unless leg

        if leg[:oi_change].to_i < min_oi_change
          return { blocked: "OI change (#{leg[:oi_change]}) below minimum (#{min_oi_change}) on #{pick[:strike]} #{expected_type}" }
        end

        iv = leg[:iv].to_f
        if iv.positive? && (iv < min_iv || iv > max_iv)
          return { blocked: "IV (#{iv.round(2)}%) outside allowed band [#{min_iv}, #{max_iv}] on #{pick[:strike]} #{expected_type}" }
        end

        delta = leg[:delta].to_f.abs
        if delta.positive? && (delta < min_delta || delta > max_delta)
          return { blocked: "delta (#{delta.round(3)}) outside allowed band [#{min_delta}, #{max_delta}] on #{pick[:strike]} #{expected_type}" }
        end

        PASS
      rescue StandardError => e
        Rails.logger.debug { "[ChainConfirmationGuard] fail-open: #{e.class} - #{e.message}" }
        PASS
      end

      def self.enabled?
        config[:enabled] != false
      end

      def self.min_oi_change
        (config[:min_oi_change] || 0).to_i
      end

      def self.min_iv
        (config[:min_iv] || 8.0).to_f
      end

      def self.max_iv
        (config[:max_iv] || 45.0).to_f
      end

      def self.min_delta
        (config[:min_delta] || 0.25).to_f
      end

      def self.max_delta
        (config[:max_delta] || 0.75).to_f
      end

      def self.config
        AlgoConfig.fetch.dig(:risk, :chain_confirmation_gate) || {}
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/entries/guards/chain_confirmation_guard_spec.rb -v`
Expected: PASS (9 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/entries/guards/chain_confirmation_guard.rb spec/services/entries/guards/chain_confirmation_guard_spec.rb
git commit -m "feat: add ChainConfirmationGuard for live OI/IV/delta entry confirmation"
```

---

### Task 4: Wire the guard into the pipeline and add config

**Files:**
- Modify: `app/services/entries/entry_guard_pipeline.rb:34` (insert into `default_handlers` array, immediately after `Guards::OptionVolumeVelocityGuard,`)
- Modify: `config/algo.yml:378-388` (add new `chain_confirmation_gate` block alongside `iv_vol_gate`/`volume_velocity_gate`)
- Test: `spec/services/entries/entry_guard_pipeline_spec.rb` (check first with `find spec/services/entries -iname "entry_guard_pipeline_spec.rb"` — if it exists, add to it; if not, this task's test is covered by Task 3's guard-level tests plus the manual verification in Step 3 below)

**Interfaces:**
- Consumes: Task 3's `Entries::Guards::ChainConfirmationGuard`.
- Produces: nothing further downstream — this is the last task, wiring everything together end to end.

- [ ] **Step 1: Check for an existing pipeline-level spec**

Run: `find /home/nemesis/project/trading-workspace/algo_scalper_api/spec/services/entries -iname "entry_guard_pipeline_spec.rb"`

If it exists, read it and add one test asserting `Guards::ChainConfirmationGuard` appears in `EntryGuardPipeline.new.send(:default_handlers)` immediately after `Guards::OptionVolumeVelocityGuard` and before `Guards::EarliestEntryGuard`. If no such spec file exists, skip to Step 2 — the guard's own behavior is already fully covered by Task 3's tests, and pipeline wiring is a one-line, visually-verifiable change.

- [ ] **Step 2: Insert the guard into the handler array**

```ruby
# In app/services/entries/entry_guard_pipeline.rb, inside default_handlers,
# change this:
        Guards::IvVolGateGuard,
        Guards::OptionVolumeVelocityGuard,
        Guards::EarliestEntryGuard,

# to this:
        Guards::IvVolGateGuard,
        Guards::OptionVolumeVelocityGuard,
        Guards::ChainConfirmationGuard,
        Guards::EarliestEntryGuard,
```

- [ ] **Step 3: Add the config block**

```yaml
# In config/algo.yml, add immediately after the existing volume_velocity_gate
# block (after line 384's "enabled: true", before the blank line + momentum_gate):

  chain_confirmation_gate:
    enabled: true
    min_oi_change: 0
    min_iv: 8.0
    max_iv: 45.0
    min_delta: 0.25
    max_delta: 0.75
```

- [ ] **Step 4: Run the full affected test suite**

Run: `bundle exec rspec spec/services/options/chain_watch_registry_spec.rb spec/services/options/chain_watch_service_spec.rb spec/lib/trading_system/bootstrap_spec.rb spec/services/entries/guards/chain_confirmation_guard_spec.rb spec/services/entries/guards/iv_vol_gate_guard_spec.rb -v`

Expected: all PASS — this confirms the new guard, the registry, the daemon wiring, and (as a regression check) the neighboring `IvVolGateGuard` are all still correct together.

- [ ] **Step 5: Sanity-check the YAML is valid**

Run: `ruby -ryaml -e "YAML.load_file('config/algo.yml'); puts 'valid'"`
Expected: `valid` (no exception)

- [ ] **Step 6: Commit**

```bash
git add app/services/entries/entry_guard_pipeline.rb config/algo.yml
git commit -m "feat: wire ChainConfirmationGuard into the entry guard pipeline"
```

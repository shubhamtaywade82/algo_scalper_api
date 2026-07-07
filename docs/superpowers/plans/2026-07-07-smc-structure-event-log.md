# SMC Structure Event Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit each atomic SMC structural event (swing high/low, BOS, CHoCH, FVG, order block, liquidity sweep) as its own append-only `smc_events` row with parent-event references, replacing the current situation where only a coarse composite "signal" snapshot gets logged.

**Architecture:** New `Smc::StructureEventRecorder` service runs the existing (already-built, currently-unused) `Smc::Detectors::*` classes against a `CandleSeries`, dedups against previously-persisted `SmcEvent` rows (by price/level identity, not array index — index shifts as the candle window slides), and publishes new events via the existing `EventStore::Publisher`. Wired into `Smc::Scanner`'s existing 5-minute poll loop. Dead code (`Smc::Analyzer`, `Smc::StructureStore`) is deleted.

**Tech Stack:** Ruby 3.3.4, Rails 8 (API-only), PostgreSQL (`smc_events` table, jsonb payload), RSpec + FactoryBot.

## Global Constraints

- Reuse `EventStore::Publisher.publish!` and the `smc_events` table exactly as they exist today — no schema changes, no new publisher.
- Gate all new writes behind the existing feature flag `AlgoConfig.fetch.dig(:signals, :smc_event_store_publish) == true` (same flag `Smc::Scanner#event_store_enabled?` already uses) — do not introduce a second flag.
- New `correlation_id` scheme for structure events: `"SMC-STRUCT-#{instrument.symbol_name}-#{interval}"` — stable per instrument/interval, NOT a random UUID. This is a deliberate deviation from the existing `TradingSignalContract`/`Scanner#publish_scan_event` pattern (which use random UUIDs per call) — do not "fix" it to match them.
- `validate_contract: false` on every `publish!` call here — the JSON-schema validation in `EventStore::Publisher` only applies to `event_type: 'signal'`, and none of our event types are `'signal'`.
- `app/services/smc/**` is an ALPHA layer per `CLAUDE.md` — safe to modify/delete freely, no Critical Scenario justification needed.
- All new detector calls must catch nothing extra — if a detector raises, let it propagate to the existing `rescue StandardError` in `Smc::Scanner#process_index`, which already logs and continues to the next index. Do not add a second layer of rescue.

---

## File Structure

- **Create:** `app/services/smc/structure_event_recorder.rb` — the whole new service, single file (all six event-type recorders as private methods; small enough to stay in one file per existing `smc/` conventions of one-class-per-concept files).
- **Create:** `spec/services/smc/structure_event_recorder_spec.rb`
- **Modify:** `app/services/smc/scanner.rb` — one new call site in `process_index`, gated identically to `publish_scan_event`.
- **Modify:** `spec/jobs/smc_scanner_job_spec.rb` or `spec/services/smc/scanner_spec.rb` (whichever covers `process_index` — see Task 7) — add coverage for the new call.
- **Delete:** `app/services/smc/analyzer.rb`, `app/services/smc/structure_store.rb` — confirmed zero live callers (`Smc::Analyzer` is never instantiated anywhere; `Smc::StructureStore` is only reachable through it). No spec files exist for either (confirmed via `spec/services/smc/` listing) — nothing to delete there.

---

### Task 1: `StructureEventRecorder` skeleton + swing events

**Files:**
- Create: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Produces: `Smc::StructureEventRecorder.record!(instrument:, interval:)` → `Array<SmcEvent>` (empty array if flag disabled or series too short). This is the only public entry point later tasks and `Smc::Scanner` will call.
- Produces (internal, used by later tasks in this same file): `#correlation_id` (String), `#event_store_enabled?` (Boolean), `#already_emitted_values(event_type:, field:)` → `Array<Float>` of previously-persisted `payload[field]` values for this correlation_id/event_type, `#publish_event!(event_type:, payload:)` → `SmcEvent`.

- [ ] **Step 1: Write the failing test for the public entry point and swing events**

```ruby
# spec/services/smc/structure_event_recorder_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::StructureEventRecorder do
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY') }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: true } })
  end

  describe '.record!' do
    it 'returns an empty array when the event store flag is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: false } })
      series = build(:candle_series, :five_minute, :with_candles)
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      expect(described_class.record!(instrument: instrument, interval: '5')).to eq([])
      expect(SmcEvent.count).to eq(0)
    end

    it 'returns an empty array when the series has fewer than 5 candles' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle))
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      expect(described_class.record!(instrument: instrument, interval: '5')).to eq([])
    end

    it 'persists a swing_high event for a detected swing high' do
      series = build(:candle_series, :five_minute)
      # Build a clean swing high at index 2: rises then falls, lookback=3 default
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 105, low: 92, close: 96),
        build(:candle, high: 120, low: 100, close: 110), # swing high candidate
        build(:candle, high: 108, low: 95, close: 97),
        build(:candle, high: 106, low: 93, close: 96),
        build(:candle, high: 104, low: 91, close: 95)
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      events = described_class.record!(instrument: instrument, interval: '5')

      swing_high_events = events.select { |e| e.event_type == 'swing_high' }
      expect(swing_high_events).not_to be_empty
      expect(swing_high_events.first.payload['price']).to eq(120.0)
      expect(swing_high_events.first.correlation_id).to eq('SMC-STRUCT-NIFTY-5')
      expect(swing_high_events.first.stream).to eq('SMC-STRUCTURE')
    end

    it 'does not re-emit a swing_high already persisted for the same correlation_id' do
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 105, low: 92, close: 96),
        build(:candle, high: 120, low: 100, close: 110),
        build(:candle, high: 108, low: 95, close: 97),
        build(:candle, high: 106, low: 93, close: 96),
        build(:candle, high: 104, low: 91, close: 95)
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      first_run = described_class.record!(instrument: instrument, interval: '5')
      second_run = described_class.record!(instrument: instrument, interval: '5')

      first_swing_highs = first_run.select { |e| e.event_type == 'swing_high' }
      second_swing_highs = second_run.select { |e| e.event_type == 'swing_high' }
      expect(first_swing_highs).not_to be_empty
      expect(second_swing_highs).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: FAIL with `uninitialized constant Smc::StructureEventRecorder`

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/smc/structure_event_recorder.rb
# frozen_string_literal: true

module Smc
  # Emits atomic structural events (swings, BOS, CHoCH, FVGs, order blocks,
  # liquidity sweeps) as append-only SmcEvent rows, one row per genuinely-new
  # event, deduped against what's already persisted for this instrument/interval.
  class StructureEventRecorder
    STREAM = 'SMC-STRUCTURE'
    MIN_CANDLES = 5

    def self.record!(instrument:, interval:)
      new(instrument: instrument, interval: interval).record!
    end

    def initialize(instrument:, interval:)
      @instrument = instrument
      @interval = interval
      @correlation_id = "SMC-STRUCT-#{instrument.symbol_name}-#{interval}"
    end

    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series)
    end

    private

    attr_reader :correlation_id

    def event_store_enabled?
      AlgoConfig.fetch.dig(:signals, :smc_event_store_publish) == true
    rescue StandardError
      false
    end

    def record_swings(series)
      swings = Smc::Detectors::Structure.new(series).swings
      known_highs = already_emitted_values(event_type: 'swing_high', field: 'price')
      known_lows = already_emitted_values(event_type: 'swing_low', field: 'price')

      events = []
      swings.each do |swing|
        price = swing[:price].to_f
        if swing[:type] == :high && known_highs.exclude?(price)
          events << publish_event!(event_type: 'swing_high', payload: { 'price' => price, 'index' => swing[:index] })
        elsif swing[:type] == :low && known_lows.exclude?(price)
          events << publish_event!(event_type: 'swing_low', payload: { 'price' => price, 'index' => swing[:index] })
        end
      end
      events
    end

    def already_emitted_values(event_type:, field:)
      SmcEvent.where(correlation_id: correlation_id, event_type: event_type)
              .order(sequence: :desc).limit(50)
              .pluck(Arel.sql("(payload->>'#{field}')::float"))
              .compact
    end

    def publish_event!(event_type:, payload:, parent_event_id: nil)
      full_payload = payload.merge('parent_event_id' => parent_event_id)
      EventStore::Publisher.publish!(
        stream: STREAM,
        event_type: event_type,
        correlation_id: correlation_id,
        payload: full_payload,
        validate_contract: false
      )
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (5 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add StructureEventRecorder with swing event emission"
```

---

### Task 2: BOS event recording

**Files:**
- Modify: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Consumes: `#already_emitted_values`, `#publish_event!`, `#correlation_id` from Task 1.
- Produces: `#record_bos(series)` → `Array<SmcEvent>`, called from `#record!`.

- [ ] **Step 1: Write the failing test**

Append to `spec/services/smc/structure_event_recorder_spec.rb`, inside the `.record!` describe block:

```ruby
    it 'persists a bos event when a break of structure occurs' do
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 89, close: 96),
        build(:candle, high: 110, low: 95, close: 111) # closes above swing high -> BOS
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 2 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }

      events = described_class.record!(instrument: instrument, interval: '5')
      bos_events = events.select { |e| e.event_type == 'bos' }

      expect(bos_events).not_to be_empty
      expect(bos_events.first.payload['type']).to eq('bullish')
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "persists a bos event"`
Expected: FAIL — no `bos` events emitted (only swing events exist so far)

- [ ] **Step 3: Implement `#record_bos`**

In `app/services/smc/structure_event_recorder.rb`, update `#record!` and add the private method:

```ruby
    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series) + record_bos(series)
    end
```

```ruby
    def record_bos(series)
      history = Smc::Detectors::Structure.new(series).bos_history
      known = already_emitted_values(event_type: 'bos', field: 'price')

      history.filter_map do |bos|
        price = bos[:price].to_f
        next if known.include?(price)

        publish_event!(event_type: 'bos', payload: { 'price' => price, 'type' => bos[:type].to_s, 'index' => bos[:index] })
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (all examples so far)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add BOS event recording to StructureEventRecorder"
```

---

### Task 3: CHoCH event recording with parent BOS reference

**Files:**
- Modify: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Consumes: `#already_emitted_values`, `#publish_event!`, `#correlation_id`.
- Produces: `#record_choch(series)` → `Array<SmcEvent>`. Each CHoCH payload includes `'parent_event_id'` pointing at the most recent persisted `'bos'` event for this `correlation_id` (queried directly, not passed in — the prior BOS may have been persisted in a previous `record!` call, not necessarily this one).

- [ ] **Step 1: Write the failing test**

```ruby
    it 'links a choch event to the most recent bos event as its parent' do
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 89, close: 96),
        build(:candle, high: 110, low: 95, close: 111),
        build(:candle, high: 109, low: 96, close: 97),
        build(:candle, high: 108, low: 80, close: 82) # closes below swing low -> CHoCH
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 2 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }

      events = described_class.record!(instrument: instrument, interval: '5')
      bos_event = events.find { |e| e.event_type == 'bos' }
      choch_event = events.find { |e| e.event_type == 'choch' }

      expect(bos_event).not_to be_nil
      expect(choch_event).not_to be_nil
      expect(choch_event.payload['parent_event_id']).to eq(bos_event.id)
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "links a choch event"`
Expected: FAIL — no `choch` events emitted

- [ ] **Step 3: Implement `#record_choch`**

```ruby
    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series) + record_bos(series) + record_choch(series)
    end
```

```ruby
    def record_choch(series)
      choch = Smc::Detectors::Structure.new(series).choch?
      return [] unless choch

      price = choch[:price].to_f
      known = already_emitted_values(event_type: 'choch', field: 'price')
      return [] if known.include?(price)

      parent_id = SmcEvent.where(correlation_id: correlation_id, event_type: 'bos')
                           .order(sequence: :desc).limit(1).pick(:id)

      [publish_event!(
        event_type: 'choch',
        payload: { 'price' => price, 'type' => choch[:type].to_s, 'index' => choch[:index] },
        parent_event_id: parent_id
      )]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (all examples so far)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add CHoCH event recording with parent BOS reference"
```

---

### Task 4: FVG event recording

**Files:**
- Modify: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Produces: `#record_fvgs(series)` → `Array<SmcEvent>`. Dedup key is `(type, from, to)` since FVG `index` shifts as the series window slides but `from`/`to` prices are stable once formed.

- [ ] **Step 1: Write the failing test**

```ruby
    it 'persists an fvg_created event for an active fair value gap' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))
      series.add_candle(build(:candle, open: 104, high: 106, low: 103, close: 105))
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:atr).with(20).and_return(1.0)

      events = described_class.record!(instrument: instrument, interval: '5')
      fvg_events = events.select { |e| e.event_type == 'fvg_created' }

      expect(fvg_events.size).to eq(1)
      expect(fvg_events.first.payload['type']).to eq('bullish')
      expect(fvg_events.first.payload['from']).to eq(102.0)
      expect(fvg_events.first.payload['to']).to eq(103.0)
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "fvg_created"`
Expected: FAIL — no `fvg_created` events emitted

- [ ] **Step 3: Implement `#record_fvgs`**

```ruby
    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series) + record_bos(series) + record_choch(series) + record_fvgs(series)
    end
```

```ruby
    def record_fvgs(series)
      gaps = Smc::Detectors::Fvg.new(series).active_gaps
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'fvg_created')
                       .order(sequence: :desc).limit(50)
                       .pluck(Arel.sql("payload->>'type'"), Arel.sql("(payload->>'from')::float"), Arel.sql("(payload->>'to')::float"))

      gaps.filter_map do |gap|
        identity = [gap[:type].to_s, gap[:from].to_f, gap[:to].to_f]
        next if known.include?(identity)

        publish_event!(
          event_type: 'fvg_created',
          payload: { 'type' => gap[:type].to_s, 'from' => gap[:from].to_f, 'to' => gap[:to].to_f, 'index' => gap[:index] }
        )
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (all examples so far)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add FVG event recording to StructureEventRecorder"
```

---

### Task 5: Order block event recording

**Files:**
- Modify: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Produces: `#record_order_blocks(series)` → `Array<SmcEvent>`. Dedup key `(bias, high, low)` — same rationale as FVG (index shifts, price levels don't).

- [ ] **Step 1: Write the failing test**

```ruby
    it 'persists an order_block_formed event for an active order block' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 105, high: 106, low: 100, close: 101)) # bearish
      series.add_candle(build(:candle, open: 101, high: 112, low: 100.5, close: 111)) # bullish displacement, closes above a.high
      series.add_candle(build(:candle, open: 111, high: 113, low: 109, close: 112))
      series.add_candle(build(:candle, open: 112, high: 114, low: 110, close: 113))
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:atr).with(20).and_return(1.0)

      events = described_class.record!(instrument: instrument, interval: '5')
      ob_events = events.select { |e| e.event_type == 'order_block_formed' }

      expect(ob_events.size).to eq(1)
      expect(ob_events.first.payload['bias']).to eq('bullish')
      expect(ob_events.first.payload['high']).to eq(106.0)
      expect(ob_events.first.payload['low']).to eq(100.0)
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "order_block_formed"`
Expected: FAIL — no `order_block_formed` events emitted

- [ ] **Step 3: Implement `#record_order_blocks`**

```ruby
    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series) + record_bos(series) + record_choch(series) +
        record_fvgs(series) + record_order_blocks(series)
    end
```

```ruby
    def record_order_blocks(series)
      blocks = Smc::Detectors::OrderBlocks.new(series).active_blocks
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'order_block_formed')
                       .order(sequence: :desc).limit(50)
                       .pluck(Arel.sql("payload->>'bias'"), Arel.sql("(payload->>'high')::float"), Arel.sql("(payload->>'low')::float"))

      blocks.filter_map do |block|
        identity = [block[:bias].to_s, block[:high].to_f, block[:low].to_f]
        next if known.include?(identity)

        publish_event!(
          event_type: 'order_block_formed',
          payload: { 'bias' => block[:bias].to_s, 'high' => block[:high].to_f, 'low' => block[:low].to_f, 'index' => block[:index] }
        )
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (all examples so far)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add order block event recording to StructureEventRecorder"
```

---

### Task 6: Liquidity sweep event recording with parent swing reference

**Files:**
- Modify: `app/services/smc/structure_event_recorder.rb`
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Produces: `#record_liquidity_sweep(series)` → `Array<SmcEvent>` (0 or 1 element — `Detectors::Liquidity` reports sweep state for the *current last candle* only, not a history). `parent_event_id` points at the `swing_high`/`swing_low` `SmcEvent` matching the swept level's price (looked up by price, since that swing was — or will be — recorded by `#record_swings` using the identical `Detectors::Structure.new(series)` default-lookback swings).
- Dedup key: `(sweep_direction, level_price, last_candle_timestamp)` — a sweep is a point-in-time event tied to one specific candle.

- [ ] **Step 1: Write the failing test**

```ruby
    it 'persists a liquidity_sweep event linked to the swept swing level' do
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 89, close: 96),
        build(:candle, high: 110, low: 95, close: 97), # swing high @ 110
        build(:candle, high: 108, low: 96, close: 98),
        build(:candle, high: 109, low: 97, close: 99),
        build(:candle, high: 115, low: 98, close: 100) # wicks above 110, closes back below -> sweep
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 2 }
      allow(series).to receive(:swing_low?) { |i| false }

      events = described_class.record!(instrument: instrument, interval: '5')
      swing_high_event = events.find { |e| e.event_type == 'swing_high' && e.payload['price'] == 110.0 }
      sweep_event = events.find { |e| e.event_type == 'liquidity_sweep' }

      expect(swing_high_event).not_to be_nil
      expect(sweep_event).not_to be_nil
      expect(sweep_event.payload['direction']).to eq('buy_side')
      expect(sweep_event.payload['parent_event_id']).to eq(swing_high_event.id)
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "liquidity_sweep event linked"`
Expected: FAIL — no `liquidity_sweep` events emitted

- [ ] **Step 3: Implement `#record_liquidity_sweep`**

```ruby
    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series) + record_bos(series) + record_choch(series) +
        record_fvgs(series) + record_order_blocks(series) + record_liquidity_sweep(series)
    end
```

```ruby
    def record_liquidity_sweep(series)
      liquidity = Smc::Detectors::Liquidity.new(series)
      direction = liquidity.sweep_direction
      return [] unless direction

      structure = Smc::Detectors::Structure.new(series)
      level_event_type = direction == :buy_side ? 'swing_high' : 'swing_low'
      level_price = (direction == :buy_side ? structure.last_swing_high : structure.last_swing_low)&.dig(:price)&.to_f
      return [] unless level_price

      last_timestamp = series.candles.last.timestamp.iso8601
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'liquidity_sweep')
                       .order(sequence: :desc).limit(50)
                       .pluck(Arel.sql("payload->>'direction'"), Arel.sql("(payload->>'level_price')::float"), Arel.sql("payload->>'timestamp'"))
      identity = [direction.to_s, level_price, last_timestamp]
      return [] if known.include?(identity)

      parent_id = SmcEvent.where(correlation_id: correlation_id, event_type: level_event_type)
                           .order(sequence: :desc).limit(50)
                           .find { |e| e.payload['price'].to_f == level_price }
                           &.id

      [publish_event!(
        event_type: 'liquidity_sweep',
        payload: { 'direction' => direction.to_s, 'level_price' => level_price, 'timestamp' => last_timestamp },
        parent_event_id: parent_id
      )]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -v`
Expected: PASS (all examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/smc/structure_event_recorder.rb spec/services/smc/structure_event_recorder_spec.rb
git commit -m "feat: add liquidity sweep event recording with parent swing reference"
```

---

### Task 7: Wire into `Smc::Scanner`

**Files:**
- Modify: `app/services/smc/scanner.rb`
- Test: `spec/jobs/smc_scanner_job_spec.rb` (existing file already exercises `Smc::Scanner` behavior via the job — check its `describe` blocks; if it does not cover `process_index` directly, add a new `spec/services/smc/scanner_spec.rb`)

**Interfaces:**
- Consumes: `Smc::StructureEventRecorder.record!(instrument:, interval:)` from Task 1.

- [ ] **Step 1: Confirm test coverage location**

Run: `bundle exec rspec spec/jobs/smc_scanner_job_spec.rb --dry-run -f documentation | grep -i "process_index\|structure"`
Expected: no output (confirms `process_index` isn't directly tested there — proceed to create a focused new spec file rather than overloading the job spec)

- [ ] **Step 2: Write the failing test**

```ruby
# spec/services/smc/scanner_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Scanner do
  describe '#process_index (private) via public start/stop lifecycle is out of scope here' do
    # process_index is private; test the StructureEventRecorder call indirectly by
    # invoking the private method via send, matching this file's narrow purpose:
    # confirming the new call site exists and is wired correctly, not re-testing
    # BiasEngine/Scanner behavior already covered by smc_scanner_job_spec.rb.
    it 'calls StructureEventRecorder.record! for the LTF interval after computing a decision' do
      scanner = described_class.new
      index_cfg = { key: 'NIFTY', sid: '13', segment: 'IDX_I' }
      instrument = create(:instrument, symbol_name: 'NIFTY', security_id: '13', segment: 'IDX_I')

      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
      bias_engine = instance_double(Smc::BiasEngine, decision: :none, ai_enabled?: false)
      allow(Smc::BiasEngine).to receive(:new).and_return(bias_engine)
      allow(scanner).to receive(:publish_scan_event)
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: true } })

      expect(Smc::StructureEventRecorder).to receive(:record!)
        .with(instrument: instrument, interval: Smc::Scanner::STRUCTURE_EVENT_INTERVAL)
        .and_return([])

      scanner.send(:process_index, index_cfg)
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/services/smc/scanner_spec.rb -v`
Expected: FAIL — `Smc::StructureEventRecorder.record!` never called (also `STRUCTURE_EVENT_INTERVAL` constant doesn't exist yet)

- [ ] **Step 4: Wire the call**

In `app/services/smc/scanner.rb`, add the constant near the other constants at the top of the class:

```ruby
    DEFAULT_PERIOD = 300
    INTER_INDEX_DELAY = 2.0 # seconds between processing indices
    DELAY_BETWEEN_CANDLE_FETCHES = 1.0 # seconds between candle fetches
    STRUCTURE_EVENT_INTERVAL = '5' # matches TradingSignalContract's default timeframe
```

Then in `process_index`, add the call right after `publish_scan_event`:

```ruby
        # Persist scan event for audit trail and replay capability
        publish_scan_event(index_cfg, instrument, decision)

        # Record atomic structural events (swings/BOS/CHoCH/FVG/OB/sweeps)
        Smc::StructureEventRecorder.record!(instrument: instrument, interval: STRUCTURE_EVENT_INTERVAL)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/services/smc/scanner_spec.rb spec/jobs/smc_scanner_job_spec.rb -v`
Expected: PASS (all examples in both files — confirms the existing job spec still passes unmodified)

- [ ] **Step 6: Commit**

```bash
git add app/services/smc/scanner.rb spec/services/smc/scanner_spec.rb
git commit -m "feat: wire StructureEventRecorder into Smc::Scanner poll loop"
```

---

### Task 8: Delete dead code

**Files:**
- Delete: `app/services/smc/analyzer.rb`
- Delete: `app/services/smc/structure_store.rb`

**Interfaces:** None — this task removes code with zero callers, verified in the design spec's investigation (`grep -rn "Smc::Analyzer\.new"` → zero hits outside the file itself; `StructureStore.new` → only reachable via the dead `Analyzer`).

- [ ] **Step 1: Re-confirm zero callers before deleting**

Run: `grep -rn "Smc::Analyzer\b" app/ lib/ spec/ config/ 2>/dev/null`
Expected: only `app/services/smc/analyzer.rb` itself (the `class Analyzer` line and internal references)

Run: `grep -rn "StructureStore\b" app/ lib/ spec/ config/ 2>/dev/null`
Expected: only `app/services/smc/analyzer.rb` (the `@store = StructureStore.new` line) and `app/services/smc/structure_store.rb` itself

- [ ] **Step 2: Delete both files**

```bash
git rm app/services/smc/analyzer.rb app/services/smc/structure_store.rb
```

- [ ] **Step 3: Run the full SMC test suite to confirm nothing broke**

Run: `bundle exec rspec spec/services/smc/ spec/jobs/smc_scanner_job_spec.rb spec/models/smc_event_spec.rb -v`
Expected: PASS, 0 failures (no spec referenced the deleted files, per the earlier `spec/services/smc/` directory listing)

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove dead Smc::Analyzer and Smc::StructureStore (zero callers)"
```

---

### Task 9: Replay determinism test

**Files:**
- Test: `spec/services/smc/structure_event_recorder_spec.rb`

**Interfaces:**
- Consumes: `EventStore::ReplayEngine.new(stream:, from:, to:)` (existing, unmodified) — `#each_event`, `#to_a`.

- [ ] **Step 1: Write the failing test**

Append to `spec/services/smc/structure_event_recorder_spec.rb`:

```ruby
  describe 'replay determinism' do
    it 'produces a stable, sequence-ordered event history replayable via EventStore::ReplayEngine' do
      instrument = create(:instrument, symbol_name: 'BANKNIFTY')
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 89, close: 96),
        build(:candle, high: 110, low: 95, close: 111),
        build(:candle, high: 109, low: 96, close: 97),
        build(:candle, high: 108, low: 80, close: 82)
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 2 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }

      described_class.record!(instrument: instrument, interval: '5')

      replay = EventStore::ReplayEngine.new(
        stream: Smc::StructureEventRecorder::STREAM,
        from: 1.minute.ago,
        to: 1.minute.from_now
      )
      sequences = replay.to_a.select { |e| e.correlation_id == 'SMC-STRUCT-BANKNIFTY-5' }.map(&:sequence)

      expect(sequences).to eq(sequences.sort)
      expect(sequences.uniq).to eq(sequences)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `bundle exec rspec spec/services/smc/structure_event_recorder_spec.rb -e "replay determinism"`
Expected: PASS if Tasks 1-6 are correctly implemented (this test doesn't add new production code — it verifies the existing `EventStore::ReplayEngine` correctly replays what `StructureEventRecorder` already writes). If it fails, the bug is in sequencing from earlier tasks — fix there, not here.

- [ ] **Step 3: Commit**

```bash
git add spec/services/smc/structure_event_recorder_spec.rb
git commit -m "test: verify structure event replay determinism via EventStore::ReplayEngine"
```

---

## Final Verification

- [ ] Run: `bundle exec rspec spec/services/smc/ spec/jobs/smc_scanner_job_spec.rb spec/models/smc_event_spec.rb`
  Expected: all green, 0 failures
- [ ] Run: `bundle exec rubocop app/services/smc/structure_event_recorder.rb app/services/smc/scanner.rb`
  Expected: no offenses
- [ ] Confirm `AlgoConfig.fetch.dig(:signals, :smc_event_store_publish)` flag exists in `config/algo.yml` (or DB overrides) before enabling in any real environment — this plan wires the call site but does not flip the flag on.

# Option Chain Scalper View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a live "naked option buying" scalping view — ATM±5 option chain (LTP, OI, IV, greeks) for NIFTY/BANKNIFTY/SENSEX, plus the existing positions panel — pushed to the SolidJS dashboard over ActionCable.

**Architecture:** A new `Options::ChainWatchService` (one instance per index) runs always-on inside the trading daemon, subscribing ATM±5 legs on `Live::MarketFeedHub` (ticker mode) and polling `Options::DerivativeChainAnalyzer#fetch_api_chain` for OI/IV/greeks. It broadcasts merged state via `ActionCable.server.broadcast` to a new `OptionChainChannel`, which the dashboard's new `OptionScalper` view subscribes to per selected index.

**Tech Stack:** Ruby 3.3.4, Rails 8 API-only, Solid Cable (ActionCable), RSpec; SolidJS + `@rails/actioncable` on the frontend.

## Global Constraints

- Never modify LOCKED files: `app/services/live/market_feed_hub.rb`, `app/services/live/tick_query.rb`, `app/services/options/derivative_chain_analyzer.rb`, `app/services/options/chain_analyzer.rb`, `lib/trading_system/supervisor.rb` internals — only call their existing public methods, and only append a new `supervisor.register(...)` line in `lib/trading_system/bootstrap.rb`.
- `Options::ChainWatchService` runs always-on as a trading-daemon service — do not gate it by `OptionChainChannel` subscribe/unsubscribe (the daemon and the web/ActionCable process do not share in-process state).
- ATM±5 legs subscribe on `Live::MarketFeedHub` in ticker mode only — never full market depth (violates the documented Sniper Subscription doctrine in `docs/OPTIONS_RESEARCH/implementation_plan.md`).
- REST chain polls must stay within Dhan's 1 req/sec quote-API limit — stagger the three index pollers.
- All percentage config values elsewhere in this repo use decimal format (`0.12` = 12%) — not applicable to this feature (no new config percentages), noted for consistency if any config is added later.

---

### Task 1: `Options::ChainWatchService` — ATM±5 leg resolution + merge state

**Files:**
- Create: `app/services/options/chain_watch_service.rb`
- Test: `spec/services/options/chain_watch_service_spec.rb`

**Interfaces:**
- Consumes: `IndexConfigLoader.load_indices` → `Array<Hash>` with `:key, :segment, :sid` (existing). `Live::TickQuery.for_security(segment:, security_id:)` → `MarketTick` or `nil` (existing). `Options::DerivativeChainAnalyzer.new(index_key:, expiry:).fetch_api_chain(expiry_str)` → `Hash` keyed by strike string, e.g. `{"25650.000000" => {"ce" => {...}, "pe" => {...}}}`, or `nil` on failure (existing). `Derivative` model columns: `underlying_symbol, expiry_date, strike_price, option_type, security_id, lot_size, exchange_segment` (existing).
- Produces: `Options::ChainWatchService.new(index_key:)` instance with `#start!`, `#stop!`, `#running?`, `#snapshot` (returns the current merged `Hash` state — used by Task 2's broadcast loop and by tests). Snapshot shape:
  ```ruby
  {
    index_key: "NIFTY",
    spot: 24800.0,
    atm_strike: 24800.0,
    expiry: "2026-07-10",
    legs: [
      {
        strike: 24750.0, type: "CE", security_id: "123", segment: "NSE_FNO",
        ltp: 120.5, oi: 45000, oi_change: 1200, iv: 14.2,
        delta: 0.52, gamma: 0.002, theta: -8.1, vega: 12.3,
        bid: 120.0, ask: 121.0, feed_stale: false
      },
      # ... 21 more legs (11 strikes × CE/PE)
    ],
    chain_stale: false,
    updated_at: "2026-07-04T10:15:00+05:30"
  }
  ```

- [ ] **Step 1: Write the failing test for ATM±5 strike resolution**

```ruby
# spec/services/options/chain_watch_service_spec.rb
require 'rails_helper'

RSpec.describe Options::ChainWatchService do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:expiry) { Date.current + 7.days }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(Live::MarketFeedHub.instance).to receive(:subscribe_many).and_return([])
    allow(Live::MarketFeedHub.instance).to receive(:unsubscribe_many).and_return([])
  end

  describe '#resolve_atm_legs' do
    it 'returns the 11 nearest strikes both sides of ATM for NIFTY' do
      # Seed 21 CE/PE derivative pairs around strike 24800 in 50pt steps
      instrument = Instrument.create!(
        exchange: 'nse', segment: 'index', security_id: '13',
        symbol_name: 'NIFTY', display_name: 'NIFTY', instrument_code: 'index'
      )
      (-10..10).each do |offset|
        strike = 24800.0 + (offset * 50)
        %w[CE PE].each do |type|
          Derivative.create!(
            instrument: instrument, exchange: 'nse', segment: 'derivatives',
            underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: strike,
            option_type: type, lot_size: 50, security_id: "#{strike.to_i}#{type}",
            symbol_name: "NIFTY-#{strike.to_i}-#{type}"
          )
        end
      end

      service = described_class.new(index_key: 'NIFTY')
      legs = service.resolve_atm_legs(spot: 24800.0, expiry: expiry)

      expect(legs.size).to eq(22) # 11 strikes × CE/PE
      strikes = legs.map { |l| l[:strike] }.uniq.sort
      expect(strikes).to eq((24550.0..25050.0).step(50).to_a)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant Options::ChainWatchService`

- [ ] **Step 3: Write minimal implementation for strike resolution**

```ruby
# app/services/options/chain_watch_service.rb
# frozen_string_literal: true

module Options
  class ChainWatchService
    STRIKE_WINDOW = 5
    POLL_INTERVAL_SECONDS = 4
    BROADCAST_INTERVAL_SECONDS = 1

    def initialize(index_key:)
      @index_key = index_key.to_s.upcase
      @index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @index_key }
      raise "unknown_index:#{@index_key}" unless @index_cfg

      @running = false
      @mutex = Mutex.new
      @snapshot = { index_key: @index_key, spot: nil, atm_strike: nil, expiry: nil, legs: [], chain_stale: true, updated_at: nil }
      @subscribed_legs = []
    end

    def running?
      @running
    end

    def snapshot
      @mutex.synchronize { @snapshot.dup }
    end

    def resolve_atm_legs(spot:, expiry:)
      increment = strike_increment_for(spot)
      atm = (spot / increment).round * increment
      strikes = (-STRIKE_WINDOW..STRIKE_WINDOW).map { |offset| atm + (offset * increment) }.select(&:positive?)

      Derivative.options
                .where(underlying_symbol: @index_key, expiry_date: expiry, strike_price: strikes)
                .where.not("security_id LIKE 'TEST_%'")
                .map do |d|
        {
          strike: d.strike_price.to_f, type: d.option_type, security_id: d.security_id.to_s,
          segment: d.exchange_segment, lot_size: d.lot_size.to_i,
          ltp: nil, oi: nil, oi_change: nil, iv: nil, delta: nil, gamma: nil, theta: nil, vega: nil,
          bid: nil, ask: nil, feed_stale: true
        }
      end
    end

    private

    def strike_increment_for(spot)
      return 25 unless spot&.positive?

      spot >= 50_000 ? 100 : (spot >= 10_000 ? 50 : 25)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/options/chain_watch_service.rb spec/services/options/chain_watch_service_spec.rb
git commit -m "feat: add Options::ChainWatchService ATM±5 strike resolution"
```

---

### Task 2: `Options::ChainWatchService` — merge live tick + REST chain data

**Files:**
- Modify: `app/services/options/chain_watch_service.rb`
- Modify: `spec/services/options/chain_watch_service_spec.rb`

**Interfaces:**
- Consumes: Task 1's `#resolve_atm_legs`. `Live::TickQuery.for_security(segment:, security_id:)` → `MarketTick` (has `.ltp, .oi, .oi_change, .bid, .ask`) or `nil`. `Options::DerivativeChainAnalyzer#fetch_api_chain(expiry_str)` → raw `oc` hash.
- Produces: `#merge_tick_data(legs)` → legs array with LTP/OI/bid/ask/feed_stale filled from `Live::TickQuery`. `#merge_chain_data(legs, api_chain)` → legs array with OI/IV/greeks filled from the REST chain (matching by strike string + type, same multi-format matching approach as `DerivativeChainAnalyzer#build_option_data`).

- [ ] **Step 1: Write the failing test for tick merge**

```ruby
# Add to spec/services/options/chain_watch_service_spec.rb

describe '#merge_tick_data' do
  it 'fills LTP/OI/bid/ask from TickQuery and clears feed_stale when a tick exists' do
    legs = [{ strike: 24800.0, type: 'CE', security_id: '24800CE', segment: 'NSE_FNO', feed_stale: true, ltp: nil, oi: nil, bid: nil, ask: nil }]
    tick = MarketTick.new(segment: 'NSE_FNO', security_id: '24800CE', ltp: 120.5, oi: 45_000, oi_change: 1200, bid: 120.0, ask: 121.0, timestamp: Time.current)
    allow(Live::TickQuery).to receive(:for_security).with(segment: 'NSE_FNO', security_id: '24800CE').and_return(tick)

    service = described_class.new(index_key: 'NIFTY')
    result = service.send(:merge_tick_data, legs)

    expect(result.first).to include(ltp: 120.5, oi: 45_000, oi_change: 1200, bid: 120.0, ask: 121.0, feed_stale: false)
  end

  it 'marks feed_stale true when TickQuery returns nil' do
    legs = [{ strike: 24800.0, type: 'CE', security_id: '24800CE', segment: 'NSE_FNO', feed_stale: false, ltp: 100.0, oi: 1, bid: 1, ask: 1 }]
    allow(Live::TickQuery).to receive(:for_security).and_return(nil)

    service = described_class.new(index_key: 'NIFTY')
    result = service.send(:merge_tick_data, legs)

    expect(result.first[:feed_stale]).to be(true)
    expect(result.first[:ltp]).to eq(100.0) # keeps last-known value
  end
end

describe '#merge_chain_data' do
  it 'fills OI/IV/greeks from the API chain matching by strike and type' do
    legs = [{ strike: 24800.0, type: 'CE', iv: nil, delta: nil, gamma: nil, theta: nil, vega: nil, oi: nil }]
    api_chain = {
      '24800.000000' => {
        'ce' => { 'oi' => 50_000, 'implied_volatility' => 14.2, 'greeks' => { 'delta' => 0.52, 'gamma' => 0.002, 'theta' => -8.1, 'vega' => 12.3 } }
      }
    }

    service = described_class.new(index_key: 'NIFTY')
    result = service.send(:merge_chain_data, legs, api_chain)

    expect(result.first).to include(oi: 50_000, iv: 14.2, delta: 0.52, gamma: 0.002, theta: -8.1, vega: 12.3)
  end

  it 'leaves legs unchanged when api_chain is nil' do
    legs = [{ strike: 24800.0, type: 'CE', iv: nil, oi: nil }]

    service = described_class.new(index_key: 'NIFTY')
    result = service.send(:merge_chain_data, legs, nil)

    expect(result).to eq(legs)
  end
end
```

(Requires `allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }])` in a shared `before` block — add it there if not already present from Task 1.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: FAIL with `NoMethodError: private method 'merge_tick_data'` (undefined until Step 3)

- [ ] **Step 3: Implement the merge methods**

```ruby
# Add to app/services/options/chain_watch_service.rb, inside the class, above `private`:

    def merge_tick_data(legs)
      legs.map do |leg|
        tick = Live::TickQuery.for_security(segment: leg[:segment], security_id: leg[:security_id])
        if tick&.ltp&.positive?
          leg.merge(
            ltp: tick.ltp.to_f, oi: tick.oi.to_i, oi_change: tick.oi_change.to_i,
            bid: tick.bid, ask: tick.ask, feed_stale: false
          )
        else
          leg.merge(feed_stale: true)
        end
      end
    end

    def merge_chain_data(legs, api_chain)
      return legs unless api_chain

      legs.map do |leg|
        strike_formats = [
          format('%<v>.6f', v: leg[:strike]), leg[:strike].to_s, leg[:strike].to_i.to_s
        ].uniq
        option_type_lower = leg[:type].to_s.downcase
        api_data = strike_formats.filter_map { |sf| api_chain.dig(sf, option_type_lower) }.first
        next leg unless api_data

        greeks = api_data['greeks'] || {}
        leg.merge(
          oi: api_data['oi']&.to_i || leg[:oi],
          iv: api_data['implied_volatility']&.to_f,
          delta: greeks['delta']&.to_f, gamma: greeks['gamma']&.to_f,
          theta: greeks['theta']&.to_f, vega: greeks['vega']&.to_f
        )
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: PASS (5 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/options/chain_watch_service.rb spec/services/options/chain_watch_service_spec.rb
git commit -m "feat: merge live tick and REST chain data in ChainWatchService"
```

---

### Task 3: `Options::ChainWatchService` — start!/stop! lifecycle, subscribe/poll/broadcast loop

**Files:**
- Modify: `app/services/options/chain_watch_service.rb`
- Modify: `spec/services/options/chain_watch_service_spec.rb`

**Interfaces:**
- Consumes: Task 1 `#resolve_atm_legs`, Task 2 `#merge_tick_data`/`#merge_chain_data`. `Live::MarketFeedHub.instance.subscribe_many(instruments)` where `instruments` is `Array<Hash>` with `:segment, :security_id` (existing). `Options::DerivativeChainAnalyzer.new(index_key:, expiry:).spot_ltp` → `Float` or `nil` (existing). `.find_nearest_expiry` → `String` (`"YYYY-MM-DD"`) or `nil` (existing). `.fetch_api_chain(expiry_str)` (existing).
- Produces: `#start!` (idempotent, spawns background thread), `#stop!` (idempotent, kills thread, unsubscribes legs), `#running?`. Broadcasts via `ActionCable.server.broadcast("option_chain_#{@index_key}", snapshot)` each cycle — this is the integration point Task 4's channel streams from.

- [ ] **Step 1: Write the failing test for start!/stop! lifecycle**

```ruby
# Add to spec/services/options/chain_watch_service_spec.rb

describe '#start! and #stop!' do
  let(:analyzer) { instance_double(Options::DerivativeChainAnalyzer) }

  before do
    allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)
    allow(analyzer).to receive(:spot_ltp).and_return(24800.0)
    allow(analyzer).to receive(:find_nearest_expiry).and_return('2026-07-10')
    allow(analyzer).to receive(:fetch_api_chain).and_return({})
    allow(ActionCable.server).to receive(:broadcast)
  end

  it 'is not running before start! and running after' do
    service = described_class.new(index_key: 'NIFTY')
    expect(service.running?).to be(false)

    service.start!
    expect(service.running?).to be(true)

    service.stop!
    expect(service.running?).to be(false)
  end

  it 'is idempotent — calling start! twice does not raise' do
    service = described_class.new(index_key: 'NIFTY')
    service.start!
    expect { service.start! }.not_to raise_error
    service.stop!
  end

  it 'subscribes resolved legs on MarketFeedHub when starting' do
    allow(Derivative).to receive(:options).and_return(Derivative.none)
    service = described_class.new(index_key: 'NIFTY')

    expect(Live::MarketFeedHub.instance).to receive(:subscribe_many).at_least(:once)
    service.start!
    service.stop!
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: FAIL with `NoMethodError: undefined method 'start!'`

- [ ] **Step 3: Implement start!/stop!/run_loop**

```ruby
# Add to app/services/options/chain_watch_service.rb, replacing the `initialize` method
# and adding the loop logic. Full class body:

# frozen_string_literal: true

module Options
  class ChainWatchService
    STRIKE_WINDOW = 5
    POLL_INTERVAL_SECONDS = 4
    BROADCAST_INTERVAL_SECONDS = 1

    def initialize(index_key:)
      @index_key = index_key.to_s.upcase
      @index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @index_key }
      raise "unknown_index:#{@index_key}" unless @index_cfg

      @running = false
      @mutex = Mutex.new
      @thread = nil
      @snapshot = { index_key: @index_key, spot: nil, atm_strike: nil, expiry: nil, legs: [], chain_stale: true, updated_at: nil }
      @subscribed_legs = []
    end

    def running?
      @running
    end

    def snapshot
      @mutex.synchronize { @snapshot.dup }
    end

    def start!
      return if running?

      @running = true
      @thread = Thread.new { run_loop }
      @thread.name = "chain-watch-#{@index_key.downcase}" if @thread.respond_to?(:name=)
    end

    def stop!
      @running = false
      @thread&.kill
      @thread&.join(1)
      @thread = nil
      unsubscribe_current_legs!
    end

    def resolve_atm_legs(spot:, expiry:)
      increment = strike_increment_for(spot)
      atm = (spot / increment).round * increment
      strikes = (-STRIKE_WINDOW..STRIKE_WINDOW).map { |offset| atm + (offset * increment) }.select(&:positive?)

      Derivative.options
                .where(underlying_symbol: @index_key, expiry_date: expiry, strike_price: strikes)
                .where.not("security_id LIKE 'TEST_%'")
                .map do |d|
        {
          strike: d.strike_price.to_f, type: d.option_type, security_id: d.security_id.to_s,
          segment: d.exchange_segment, lot_size: d.lot_size.to_i,
          ltp: nil, oi: nil, oi_change: nil, iv: nil, delta: nil, gamma: nil, theta: nil, vega: nil,
          bid: nil, ask: nil, feed_stale: true
        }
      end
    end

    private

    def run_loop
      last_poll_at = Time.at(0)

      while running?
        begin
          analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key)
          spot = analyzer.spot_ltp
          expiry = analyzer.find_nearest_expiry

          if spot&.positive? && expiry
            legs = resolve_atm_legs(spot: spot, expiry: Date.parse(expiry))
            resubscribe_legs!(legs)

            chain_stale = false
            if Time.current - last_poll_at >= POLL_INTERVAL_SECONDS
              api_chain = analyzer.fetch_api_chain(expiry)
              chain_stale = api_chain.nil?
              legs = merge_chain_data(legs, api_chain)
              last_poll_at = Time.current
            end
            legs = merge_tick_data(legs)

            @mutex.synchronize do
              @snapshot = {
                index_key: @index_key, spot: spot, atm_strike: nearest_atm(spot, legs),
                expiry: expiry, legs: legs, chain_stale: chain_stale, updated_at: Time.current.iso8601
              }
            end

            ActionCable.server.broadcast("option_chain_#{@index_key}", snapshot)
          end
        rescue StandardError => e
          Rails.logger.error("[ChainWatchService:#{@index_key}] #{e.class} - #{e.message}")
        end

        sleep BROADCAST_INTERVAL_SECONDS
      end
    end

    def resubscribe_legs!(new_legs)
      new_keys = new_legs.map { |l| { segment: l[:segment], security_id: l[:security_id] } }
      old_keys = @subscribed_legs

      to_add = new_keys - old_keys
      to_remove = old_keys - new_keys

      Live::MarketFeedHub.instance.subscribe_many(to_add) if to_add.any?
      Live::MarketFeedHub.instance.unsubscribe_many(to_remove) if to_remove.any?

      @subscribed_legs = new_keys
    end

    def unsubscribe_current_legs!
      Live::MarketFeedHub.instance.unsubscribe_many(@subscribed_legs) if @subscribed_legs.any?
      @subscribed_legs = []
    end

    def nearest_atm(spot, legs)
      strikes = legs.map { |l| l[:strike] }.uniq
      return nil if strikes.empty?

      strikes.min_by { |s| (s - spot).abs }
    end

    def merge_tick_data(legs)
      legs.map do |leg|
        tick = Live::TickQuery.for_security(segment: leg[:segment], security_id: leg[:security_id])
        if tick&.ltp&.positive?
          leg.merge(
            ltp: tick.ltp.to_f, oi: tick.oi.to_i, oi_change: tick.oi_change.to_i,
            bid: tick.bid, ask: tick.ask, feed_stale: false
          )
        else
          leg.merge(feed_stale: true)
        end
      end
    end

    def merge_chain_data(legs, api_chain)
      return legs unless api_chain

      legs.map do |leg|
        strike_formats = [
          format('%<v>.6f', v: leg[:strike]), leg[:strike].to_s, leg[:strike].to_i.to_s
        ].uniq
        option_type_lower = leg[:type].to_s.downcase
        api_data = strike_formats.filter_map { |sf| api_chain.dig(sf, option_type_lower) }.first
        next leg unless api_data

        greeks = api_data['greeks'] || {}
        leg.merge(
          oi: api_data['oi']&.to_i || leg[:oi],
          iv: api_data['implied_volatility']&.to_f,
          delta: greeks['delta']&.to_f, gamma: greeks['gamma']&.to_f,
          theta: greeks['theta']&.to_f, vega: greeks['vega']&.to_f
        )
      end
    end

    def strike_increment_for(spot)
      return 25 unless spot&.positive?

      spot >= 50_000 ? 100 : (spot >= 10_000 ? 50 : 25)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb -v`
Expected: PASS (all examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/options/chain_watch_service.rb spec/services/options/chain_watch_service_spec.rb
git commit -m "feat: add ChainWatchService start!/stop! loop with subscribe/poll/broadcast"
```

---

### Task 4: Register `ChainWatchService` instances in the trading daemon

**Files:**
- Modify: `lib/trading_system/bootstrap.rb:47-73` (inside `build_supervisor`)
- Test: `spec/lib/trading_system/bootstrap_spec.rb` (create if it doesn't exist; check first with `find spec/lib/trading_system -iname "bootstrap*"`)

**Interfaces:**
- Consumes: `Options::ChainWatchService.new(index_key:)` (Task 3). `TradingSystem::Supervisor#register(key, service)` (existing — takes any object responding to service lifecycle; confirm exact required interface by reading `lib/trading_system/supervisor.rb` before writing this task's code, since the plan author has not yet inspected the full `Supervisor#register` contract beyond its usage sites in `bootstrap.rb`).
- Produces: three new supervisor entries: `:chain_watch_nifty`, `:chain_watch_banknifty`, `:chain_watch_sensex`.

- [ ] **Step 1: Read `lib/trading_system/supervisor.rb` to confirm the `#register` contract**

Run: `cat lib/trading_system/supervisor.rb`

Confirm what interface `register(key, service)` expects from `service` (e.g. does it call `.start` or `.start!`? `.stop` or `.stop!`?). `ChainWatchService` from Task 3 exposes `start!`/`stop!`/`running?` — if `Supervisor` expects `start`/`stop` (no bang) based on this read, add matching non-bang aliases to `ChainWatchService` in this step before proceeding (do not rename the bang versions — other tests from Tasks 1-3 depend on them).

- [ ] **Step 2: Write the failing test**

```ruby
# spec/lib/trading_system/bootstrap_spec.rb
require 'rails_helper'

RSpec.describe TradingSystem::Bootstrap do
  describe '.build_supervisor' do
    it 'registers a ChainWatchService for each of NIFTY, BANKNIFTY, SENSEX' do
      supervisor = described_class.build_supervisor
      registered = supervisor.instance_variable_get(:@services) || supervisor.instance_variable_get(:@registry)

      expect(registered.keys).to include(:chain_watch_nifty, :chain_watch_banknifty, :chain_watch_sensex)
      expect(registered[:chain_watch_nifty]).to be_a(Options::ChainWatchService)
    end
  end
end
```

(If `Supervisor` stores registrations under a different ivar name than `@services`/`@registry`, adjust after reading it in Step 1 — inspect via `supervisor.rb`'s `register` method body to find the actual ivar.)

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/trading_system/bootstrap_spec.rb -v`
Expected: FAIL — registered keys do not include `:chain_watch_nifty`

- [ ] **Step 4: Add the registrations**

```ruby
# In lib/trading_system/bootstrap.rb, inside build_supervisor, before the final `supervisor` line:

      supervisor.register(:chain_watch_nifty, Options::ChainWatchService.new(index_key: 'NIFTY'))
      supervisor.register(:chain_watch_banknifty, Options::ChainWatchService.new(index_key: 'BANKNIFTY'))
      supervisor.register(:chain_watch_sensex, Options::ChainWatchService.new(index_key: 'SENSEX'))
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/trading_system/bootstrap_spec.rb -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/trading_system/bootstrap.rb spec/lib/trading_system/bootstrap_spec.rb
git commit -m "feat: register ChainWatchService instances in trading daemon supervisor"
```

---

### Task 5: `OptionChainChannel`

**Files:**
- Create: `app/channels/option_chain_channel.rb`
- Test: `spec/channels/option_chain_channel_spec.rb`

**Interfaces:**
- Consumes: `params[:index_key]` (client-supplied string, e.g. `"NIFTY"`).
- Produces: on `subscribed`, calls `stream_from "option_chain_#{params[:index_key]}"` — this is the stream name Task 3's `ChainWatchService#run_loop` broadcasts to.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/channels/option_chain_channel_spec.rb
require 'rails_helper'

RSpec.describe OptionChainChannel, type: :channel do
  it 'streams from the index-specific channel name' do
    subscribe(index_key: 'NIFTY')
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from('option_chain_NIFTY')
  end

  it 'streams from a different index when a different index_key is given' do
    subscribe(index_key: 'BANKNIFTY')
    expect(subscription).to have_stream_from('option_chain_BANKNIFTY')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/channels/option_chain_channel_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant OptionChainChannel`

- [ ] **Step 3: Implement the channel**

```ruby
# app/channels/option_chain_channel.rb
# frozen_string_literal: true

# Streams live option-chain snapshots (spot, ATM±5 legs with LTP/OI/IV/greeks) per index.
# Broadcasts:
#   { index_key:, spot:, atm_strike:, expiry:, legs: [...], chain_stale:, updated_at: }
# Fed by Options::ChainWatchService running in the trading daemon (see docs/superpowers/specs/2026-07-04-option-chain-scalper-view-design.md).
class OptionChainChannel < ApplicationCable::Channel
  def subscribed
    index_key = params[:index_key].to_s.upcase
    stream_from "option_chain_#{index_key}"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/channels/option_chain_channel_spec.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/channels/option_chain_channel.rb spec/channels/option_chain_channel_spec.rb
git commit -m "feat: add OptionChainChannel streaming per-index option chain data"
```

---

### Task 6: Frontend store `useOptionChain.js`

**Files:**
- Create: `dashboard/src/stores/useOptionChain.js`

**Interfaces:**
- Consumes: `cable.js` default export (existing `createConsumer` instance). Subscribes to `OptionChainChannel` with `{ index_key }`.
- Produces: `useOptionChain(indexKey)` hook returning `{ chain, connected, isStale }` where `chain()` is a SolidJS signal holding the latest broadcast payload (or `null` before first message), matching the shape from Task 3's `ChainWatchService` snapshot (`spot, atm_strike, expiry, legs, chain_stale, updated_at`). Later tasks (7, 8) consume `chain()`, `connected()`, `isStale()`.

- [ ] **Step 1: Write the file**

```javascript
// dashboard/src/stores/useOptionChain.js
import { createSignal, onCleanup, createEffect } from 'solid-js'
import cable from '../cable'

const STALE_AFTER_MS = 5000

export function useOptionChain(indexKey) {
  const [chain, setChain] = createSignal(null)
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)

  let subscription = null
  let staleTimer = null

  function markFresh() {
    setIsStale(false)
    clearTimeout(staleTimer)
    staleTimer = setTimeout(() => setIsStale(true), STALE_AFTER_MS)
  }

  function subscribeToIndex(key) {
    subscription?.unsubscribe()
    clearTimeout(staleTimer)
    setChain(null)
    setIsStale(true)

    subscription = cable.subscriptions.create(
      { channel: 'OptionChainChannel', index_key: key },
      {
        connected() {
          setConnected(true)
          markFresh()
        },
        disconnected() {
          setConnected(false)
        },
        received(data) {
          markFresh()
          setChain(data)
        }
      }
    )
  }

  createEffect(() => {
    const key = typeof indexKey === 'function' ? indexKey() : indexKey
    if (key) subscribeToIndex(key)
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearTimeout(staleTimer)
  })

  return { chain, connected, isStale }
}
```

- [ ] **Step 2: Manual verification (no JS unit test harness for stores in this repo — confirm by grep)**

Run: `grep -rl "\.test\.js\|\.spec\.js" dashboard/src/stores/ || echo "no store unit tests exist in this repo"`
Expected: confirms no existing store-level JS test convention to match — this store will be verified via the Task 8 manual smoke test instead, consistent with `usePositions.js` (also untested directly).

- [ ] **Step 3: Commit**

```bash
cd dashboard && git add src/stores/useOptionChain.js
git commit -m "feat: add useOptionChain store for live option chain WS data"
```

---

### Task 7: Frontend `OptionChainTable` component + `OptionScalper` view

**Files:**
- Create: `dashboard/src/components/OptionChainTable.jsx`
- Create: `dashboard/src/views/OptionScalper.jsx`

**Interfaces:**
- Consumes: Task 6's `useOptionChain(indexKey)` → `{ chain, connected, isStale }`. `chain().legs` → array of leg objects (`strike, type, ltp, oi, oi_change, iv, delta, bid, ask, feed_stale`). `chain().atm_strike`. Existing `useDashboardContext()` (from `dashboard/src/context/DashboardContext.jsx`) for `open` (positions array) and `circuitBreaker`, to pass into the reused `OpenPositions` component. Existing `OpenPositions` component props: `positions`, `circuitBreaker`, `wsConnected`, `wsStale` (confirmed from `dashboard/src/components/OpenPositions.jsx`).
- Produces: `OptionScalper` view mounted at route `/option-scalper` (wired in Task 8).

- [ ] **Step 1: Write `OptionChainTable.jsx`**

```jsx
// dashboard/src/components/OptionChainTable.jsx
import { Index, Show } from 'solid-js'

function fmt(n, digits = 2) {
  return n == null ? '—' : Number(n).toFixed(digits)
}

export default function OptionChainTable(props) {
  const legs = () => props.chain?.legs || []
  const atmStrike = () => props.chain?.atm_strike

  const strikeRows = () => {
    const byStrike = {}
    legs().forEach(leg => {
      byStrike[leg.strike] ||= { strike: leg.strike, ce: null, pe: null }
      byStrike[leg.strike][leg.type.toLowerCase()] = leg
    })
    return Object.values(byStrike).sort((a, b) => a.strike - b.strike)
  }

  return (
    <div class="glass rounded-2xl overflow-hidden mt-6">
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.02]">
        <h2 class="text-sm font-bold text-white uppercase tracking-[0.2em]">
          {props.indexKey} Option Chain
          <Show when={props.chain?.spot}>
            <span class="text-primary-400 ml-2 font-black text-data">Spot {fmt(props.chain.spot)}</span>
          </Show>
        </h2>
        <div class={`text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full border ${props.isStale ? 'text-amber-300 bg-amber-500/10 border-amber-500/30' : 'text-cyan-300 bg-cyan-500/10 border-cyan-500/30'}`}>
          {props.isStale ? 'STALE' : 'LIVE'}
        </div>
      </div>

      <Show when={strikeRows().length > 0} fallback={<div class="p-10 text-center text-gray-600 text-xs uppercase tracking-widest">Waiting for chain data...</div>}>
        <div class="overflow-x-auto">
          <table class="w-full border-collapse text-xs">
            <thead>
              <tr class="text-[10px] text-gray-400 uppercase tracking-[0.15em] border-b border-white/5 bg-white/[0.02]">
                <th class="text-right px-3 py-2">CE Delta</th>
                <th class="text-right px-3 py-2">CE IV</th>
                <th class="text-right px-3 py-2">CE OI</th>
                <th class="text-right px-3 py-2">CE LTP</th>
                <th class="text-center px-3 py-2">Strike</th>
                <th class="text-left px-3 py-2">PE LTP</th>
                <th class="text-left px-3 py-2">PE OI</th>
                <th class="text-left px-3 py-2">PE IV</th>
                <th class="text-left px-3 py-2">PE Delta</th>
              </tr>
            </thead>
            <tbody>
              <Index each={strikeRows()}>
                {row => (
                  <tr class={`border-b border-white/5 ${row().strike === atmStrike() ? 'bg-primary-500/10' : ''}`}>
                    <td class="text-right px-3 py-2">{fmt(row().ce?.delta, 3)}</td>
                    <td class="text-right px-3 py-2">{fmt(row().ce?.iv)}</td>
                    <td class="text-right px-3 py-2">{row().ce?.oi ?? '—'}</td>
                    <td class="text-right px-3 py-2 font-bold">{fmt(row().ce?.ltp)}</td>
                    <td class="text-center px-3 py-2 font-black">{row().strike}</td>
                    <td class="text-left px-3 py-2 font-bold">{fmt(row().pe?.ltp)}</td>
                    <td class="text-left px-3 py-2">{row().pe?.oi ?? '—'}</td>
                    <td class="text-left px-3 py-2">{fmt(row().pe?.iv)}</td>
                    <td class="text-left px-3 py-2">{fmt(row().pe?.delta, 3)}</td>
                  </tr>
                )}
              </Index>
            </tbody>
          </table>
        </div>
      </Show>
    </div>
  )
}
```

- [ ] **Step 2: Write `OptionScalper.jsx`**

```jsx
// dashboard/src/views/OptionScalper.jsx
import { createSignal } from 'solid-js'
import { useOptionChain } from '../stores/useOptionChain'
import { useDashboardContext } from '../context/DashboardContext'
import OptionChainTable from '../components/OptionChainTable'
import OpenPositions from '../components/OpenPositions'

const INDICES = ['NIFTY', 'BANKNIFTY', 'SENSEX']

export default function OptionScalper() {
  const [selectedIndex, setSelectedIndex] = createSignal('NIFTY')
  const { chain, isStale } = useOptionChain(selectedIndex)
  const { open, circuitBreaker, positionsConnected, positionsStale } = useDashboardContext()

  return (
    <div>
      <div class="flex gap-2 mb-4">
        {INDICES.map(idx => (
          <button
            class={`px-4 py-2 rounded-lg text-xs font-black uppercase tracking-widest border ${selectedIndex() === idx ? 'bg-primary-500/20 border-primary-500/40 text-primary-300' : 'bg-white/5 border-white/10 text-gray-400'}`}
            onClick={() => setSelectedIndex(idx)}
          >
            {idx}
          </button>
        ))}
      </div>

      <OptionChainTable indexKey={selectedIndex()} chain={chain()} isStale={isStale()} />

      <OpenPositions
        positions={open()}
        circuitBreaker={circuitBreaker()}
        wsConnected={positionsConnected()}
        wsStale={positionsStale()}
      />
    </div>
  )
}
```

- [ ] **Step 3: Commit**

```bash
cd dashboard && git add src/components/OptionChainTable.jsx src/views/OptionScalper.jsx
git commit -m "feat: add OptionChainTable and OptionScalper view"
```

---

### Task 8: Wire the route and nav entry; manual smoke test

**Files:**
- Modify: `dashboard/src/App.jsx:9-17` (lazy imports), `:83-91` (routes inside `AppShell`)
- Modify: `dashboard/src/components/Header.jsx` (nav links block, around line 284-323)

**Interfaces:**
- Consumes: Task 7's `OptionScalper` default export.
- Produces: route `/option-scalper` reachable from the nav.

- [ ] **Step 1: Add the lazy import and route in `App.jsx`**

```jsx
// In dashboard/src/App.jsx, add alongside the other lazy imports (after the TrailEngine line):
const OptionScalper = lazy(() => import('./views/OptionScalper'))
```

```jsx
// In the <Route component={AppShell}> block, add a new route alongside the existing ones:
        <Route path="/option-scalper" component={OptionScalper} />
```

- [ ] **Step 2: Add the nav link in `Header.jsx`**

```jsx
// Add alongside the existing <A href="/signals" ...> block (same navLinkBase/navLinkInactive/navLinkActive pattern):
          <A href="/option-scalper" class={`${navLinkBase} ${navLinkInactive}`} activeClass={navLinkActive} inactiveClass="">
            Option Scalper
          </A>
```

(Match the exact JSX children/icon pattern used by the neighboring `<A>` tags in `Header.jsx` — read the surrounding lines first since each nav link has slightly different icon markup inside.)

- [ ] **Step 3: Run the full backend test suite**

Run: `bundle exec rspec spec/services/options/chain_watch_service_spec.rb spec/lib/trading_system/bootstrap_spec.rb spec/channels/option_chain_channel_spec.rb -v`
Expected: all PASS

- [ ] **Step 4: Manual smoke test during market hours**

Start the app: `./bin/dev` (starts web, trading daemon, jobs, dashboard per `Procfile.dev`).

Open `http://localhost:3011` (or the dashboard's dev port per `dashboard/vite.config.js`), navigate to "Option Scalper" in the nav. Verify:
- All three index tabs (NIFTY/BANKNIFTY/SENSEX) show a populated chain table within a few seconds of switching.
- ATM row is highlighted.
- LTP/OI/IV/greeks values look plausible (non-zero, IV roughly 8-30% range for index options).
- Switching tabs updates the displayed chain without a full page reload.
- "STALE" badge appears if you stop the trading daemon process and disappears when it's running again.
- Positions panel at the bottom still works exactly as it does on the existing Dashboard view (no regression).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/App.jsx dashboard/src/components/Header.jsx
git commit -m "feat: wire Option Scalper route and nav entry"
```

# Resilience / Self-Healing Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 5 verified resilience gaps (no crash auto-restart, dead in-memory tick cache, unused WS health hooks, a reconciliation fallback that lies about broker state, and an unwired double-entry lock) plus 3 bugs discovered while reading the same files (a duplicate method silently dropping a boot step, a `start!` fall-through that reports success after failure, and a missing shutdown alert for open positions — the last two surfaced via pre-existing failing specs).

**Architecture:** No new files, no new abstractions. Every fix is a surgical edit to an existing file: `lib/trading_system/daemon.rb`, `lib/trading_system/supervisor.rb`, `app/services/tick_cache.rb`, `app/services/live/market_feed_hub.rb`, `app/services/live/reconciliation_service.rb`, `app/services/entries/entry_guard.rb`.

**Tech Stack:** Ruby 3.3.4, Rails 8 API-only, DhanHQ gem 3.3.0, RSpec, PostgreSQL advisory locks.

## Global Constraints

- No new background threads for the health-check watchdog — piggyback on `Daemon#keep_process_alive!`'s existing 1-second loop with a counter (per approved design).
- No `AlgoConfig`/env-var knobs for the new constants (health-check interval, tick-cache memory TTL) unless a task discovers a concrete reason one's needed — hardcoded per YAGNI.
- `Entries::AdvisoryLock` in Task 5 wraps through the order-placement network call (approved deviation from the original design doc, which assumed the lock could stop short of it — the code doesn't allow that without a bigger restructure; see spec `docs/superpowers/specs/2026-08-05-resilience-self-healing-audit-design.md` section 5).
- Every existing spec in the files this plan touches must still pass after each task — this is a live-trading daemon, not incidental coverage.
- Two tasks (1 and 4) implement against **pre-existing failing specs already committed to the repo** (`spec/lib/trading_system/daemon_shutdown_spec.rb`, `spec/services/live/reconciliation_service_stuck_exit_spec.rb`) rather than new ones — those specs are more precise than anything written fresh, since they were apparently written ahead of the implementation. Don't rewrite them; make them pass.

---

## Task 1: Daemon/Supervisor crash detection, auto-restart, and two bugs in the same files

**Files:**
- Modify: `lib/trading_system/daemon.rb`
- Modify: `lib/trading_system/supervisor.rb`
- Test: `spec/lib/trading_system/daemon_shutdown_spec.rb` (existing, currently 1 of 2 failing — implement against it, don't edit it)
- Test: `spec/lib/trading_system/daemon_health_watchdog_spec.rb` (new)
- Test: `spec/services/trading_system/supervisor_spec.rb` (new, or extend if one already exists — check first)

**Interfaces:**
- Consumes: `TradingSystem::Supervisor#health_check` (made public this task), `#restart_service(name)` (existing, public), `Notifications::TelegramNotifier.instance.notify_error(message, context:)` (existing pattern, used elsewhere in this file already for `Daemon#start`'s rescue).
- Produces: no public interface change to `Daemon` — `keep_process_alive!` and `safe_stop!` stay private, same call signature.

- [ ] **Step 1: Check for an existing Supervisor spec file**

Run: `find spec -iname "*supervisor*"`
If `spec/services/trading_system/supervisor_spec.rb` or similar exists, read it and extend it in Step 3 instead of creating a new file. If none exists (only `spec/initializers/trading_supervisor_spec.rb`, which tests the Rails initializer, not the class directly), create `spec/services/trading_system/supervisor_spec.rb` in Step 3.

- [ ] **Step 2: Run the pre-existing failing daemon spec to confirm current state**

Run: `bundle exec rspec spec/lib/trading_system/daemon_shutdown_spec.rb`
Expected: 1 failure — `TradingSystem::Daemon#safe_stop! alerts with the open-position count before stopping services`, with `Notifications::TelegramNotifier.instance` `received: 0 times` instead of the expected alert call.

- [ ] **Step 3: Write the failing test for Supervisor#health_check being public and callable**

Create `spec/services/trading_system/supervisor_spec.rb` (or add to the existing file found in Step 1):

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Supervisor do
  let(:supervisor) { described_class.new }

  describe '#health_check' do
    it 'is a public method' do
      expect(supervisor.public_methods(false)).to include(:health_check)
    end

    it 'reports true for a service with no health method' do
      supervisor.register(:no_health, Object.new)
      expect(supervisor.health_check).to eq(no_health: true)
    end

    it 'reports healthy? result when the service defines it' do
      healthy_service = double('Service', healthy?: false)
      supervisor.register(:flaky, healthy_service)
      expect(supervisor.health_check).to eq(flaky: false)
    end

    it 'reports running? result when the service defines it but not healthy?' do
      running_service = double('Service', running?: false)
      supervisor.register(:stopped, running_service)
      expect(supervisor.health_check).to eq(stopped: false)
    end

    it 'reports false if the health check itself raises' do
      broken_service = double('Service')
      allow(broken_service).to receive(:healthy?).and_raise('boom')
      supervisor.register(:broken, broken_service)
      expect(supervisor.health_check).to eq(broken: false)
    end
  end
end
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bundle exec rspec spec/services/trading_system/supervisor_spec.rb`
Expected: FAIL on the "is a public method" example — `health_check` is currently private, so `public_methods(false)` won't include it. (The other 4 examples may pass already via `send`-free direct calls failing with `NoMethodError: private method`, or may all fail the same way depending on RSpec's handling — either way, at least one failure confirms the gap.)

- [ ] **Step 5: Make `health_check` public in `lib/trading_system/supervisor.rb`**

The method currently sits after the `private` keyword (line 87) at lines 107-119. Move its definition to just above the `private` line (i.e., make it the last public method, right after `restart_service`):

```ruby
    def restart_service(name)
      name = name.to_sym
      @mutex.synchronize do
        raise "Unknown service: #{name}" unless @services.key?(name)

        stop_one(name)
        start_one(name)
      end
    end

    # Best-effort health snapshot for use by API health endpoints.
    # Returns a hash keyed by service name with boolean statuses.
    def health_check
      @services.transform_values do |svc|
        if svc.respond_to?(:healthy?)
          svc.healthy?
        elsif svc.respond_to?(:running?)
          svc.running?
        else
          true
        end
      rescue StandardError
        false
      end
    end

    private
```

Delete the old `health_check` definition from its current location (after `stop_one`, before the final `end end`).

- [ ] **Step 6: Run the supervisor spec to verify it passes**

Run: `bundle exec rspec spec/services/trading_system/supervisor_spec.rb`
Expected: PASS — all 5 examples green.

- [ ] **Step 7: Commit**

```bash
git add lib/trading_system/supervisor.rb spec/services/trading_system/supervisor_spec.rb
git commit -m "Make Supervisor#health_check public

Needed so Daemon's watchdog loop (next commit) can poll it. Was
private with zero callers anywhere in the codebase."
```

- [ ] **Step 8: Write the failing test for the daemon's health watchdog**

Create `spec/lib/trading_system/daemon_health_watchdog_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Daemon do
  describe '#check_service_health!' do
    let(:supervisor) { instance_double(TradingSystem::Supervisor) }
    let(:daemon) { described_class.new(supervisor: supervisor) }

    before do
      allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
    end

    it 'restarts and alerts for each unhealthy service' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: false, signal_scheduler: true)
      allow(supervisor).to receive(:restart_service)

      daemon.send(:check_service_health!)

      expect(supervisor).to have_received(:restart_service).with(:risk_manager).once
      expect(supervisor).not_to have_received(:restart_service).with(:signal_scheduler)
      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
        a_string_matching(/risk_manager/),
        context: 'TradingSystem::Daemon#check_service_health!'
      )
    end

    it 'does nothing when all services are healthy' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: true)
      allow(supervisor).to receive(:restart_service)

      daemon.send(:check_service_health!)

      expect(supervisor).not_to have_received(:restart_service)
      expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_error)
    end

    it 'does not raise if restart_service itself fails' do
      allow(supervisor).to receive(:health_check).and_return(risk_manager: false)
      allow(supervisor).to receive(:restart_service).and_raise('restart failed')

      expect { daemon.send(:check_service_health!) }.not_to raise_error
    end

    it 'is a no-op when there is no supervisor' do
      daemon_without_supervisor = described_class.new(supervisor: nil)
      expect { daemon_without_supervisor.send(:check_service_health!) }.not_to raise_error
    end
  end
end
```

- [ ] **Step 9: Run it to verify it fails**

Run: `bundle exec rspec spec/lib/trading_system/daemon_health_watchdog_spec.rb`
Expected: FAIL with `NoMethodError: private method 'check_service_health!' called` or undefined method — the method doesn't exist yet.

- [ ] **Step 10: Implement the watchdog in `lib/trading_system/daemon.rb`**

Add the constant next to `MARKET_OPEN_POLL_INTERVAL`:

```ruby
    MARKET_OPEN_POLL_INTERVAL = 60 # seconds
    HEALTH_CHECK_INTERVAL = 30 # seconds (keep_process_alive! loop runs at 1s cadence)
```

Replace `keep_process_alive!` (currently just watching `@shutdown_requested` and sleeping 1s) with:

```ruby
    def keep_process_alive!
      ticks_since_health_check = 0

      loop do
        if @shutdown_requested
          Rails.logger.info("[TradingDaemon] Received #{@shutdown_requested}, shutting down...")
          safe_stop!
          break
        end

        ticks_since_health_check += 1
        if ticks_since_health_check >= HEALTH_CHECK_INTERVAL
          ticks_since_health_check = 0
          check_service_health!
        end

        sleep 1
      end
    end

    def check_service_health!
      return unless @supervisor

      @supervisor.health_check.each do |name, healthy|
        next if healthy

        Rails.logger.error("[TradingDaemon] Service #{name} reported unhealthy - restarting")
        Notifications::TelegramNotifier.instance.notify_error(
          "Service #{name} unhealthy, restarting",
          context: 'TradingSystem::Daemon#check_service_health!'
        )
        @supervisor.restart_service(name)
      rescue StandardError => e
        Rails.logger.error("[TradingDaemon] Failed to restart #{name}: #{e.class} - #{e.message}")
      end
    end
```

- [ ] **Step 11: Run the watchdog spec to verify it passes**

Run: `bundle exec rspec spec/lib/trading_system/daemon_health_watchdog_spec.rb`
Expected: PASS — all 4 examples green.

- [ ] **Step 12: Fix the duplicate `start_market_open_poller!` definition**

`lib/trading_system/daemon.rb` currently defines this method twice:
- Lines 75-88 (first): calls `start_full_trading_services!` (includes `boot_market_gates!`)
- Lines 96-110 (second, wins silently): inlines `@supervisor.start_all` + `subscribe_active_positions!`, **missing** `boot_market_gates!`

Delete the second definition entirely (lines 96-110):

```ruby
    def start_market_open_poller!
      @market_open_thread = Thread.new do
        Thread.current.name = 'daemon-market-open-poller'
        loop do
          sleep MARKET_OPEN_POLL_INTERVAL
          next if TradingSession::Service.market_closed?

          Rails.logger.info('[TradingDaemon] Market opened - starting remaining services')
          @supervisor.start_all
          subscribe_active_positions!
          Rails.logger.info('[TradingDaemon] Full services started')
          break
        end
      end
    end
```

Leave the first definition (lines 75-88) as the only one.

- [ ] **Step 13: Run the full daemon-related spec files to confirm no regression from the duplicate-method fix**

Run: `bundle exec rspec spec/lib/trading_system/ spec/initializers/trading_supervisor_spec.rb`
Expected: still only the known `safe_stop!` alert failure (Step 2's baseline) — nothing new broken. `start_market_open_poller!` has no direct spec (it's exercised only via a live 60s sleep loop), so removing the dead duplicate shouldn't move any test.

- [ ] **Step 14: Implement the `safe_stop!` open-position alert against the pre-existing spec**

The spec (`spec/lib/trading_system/daemon_shutdown_spec.rb`) expects a message matching `/3 open position\(s\).*UNMONITORED/` with `context: 'TradingSystem::Daemon#safe_stop!'`, sent only when `PositionTracker.active.count` is nonzero.

Replace `safe_stop!` in `lib/trading_system/daemon.rb`:

```ruby
    def safe_stop!
      alert_open_positions!

      if @market_open_thread&.alive?
        @market_open_thread.kill
        @market_open_thread = nil
      end
      @supervisor&.stop_all
    rescue StandardError => e
      warn "[TradingDaemon] safe_stop! failed: #{e.class} - #{e.message}"
    end

    def alert_open_positions!
      count = PositionTracker.active.count
      return if count.zero?

      Notifications::TelegramNotifier.instance.notify_error(
        "Daemon shutting down with #{count} open position(s) - they will be UNMONITORED until restart",
        context: 'TradingSystem::Daemon#safe_stop!'
      )
    rescue StandardError => e
      warn "[TradingDaemon] alert_open_positions! failed: #{e.class} - #{e.message}"
    end
```

- [ ] **Step 15: Run the pre-existing daemon shutdown spec to verify it now passes**

Run: `bundle exec rspec spec/lib/trading_system/daemon_shutdown_spec.rb`
Expected: PASS — both examples green.

- [ ] **Step 16: Run the full set of files touched in this task**

Run: `bundle exec rspec spec/lib/trading_system/ spec/services/trading_system/ spec/initializers/trading_supervisor_spec.rb`
Expected: PASS — everything green.

- [ ] **Step 17: Commit**

```bash
git add lib/trading_system/daemon.rb spec/lib/trading_system/daemon_health_watchdog_spec.rb spec/services/trading_system/supervisor_spec.rb
git commit -m "Add daemon health watchdog, fix duplicate method, alert on shutdown with open positions

- keep_process_alive! now polls Supervisor#health_check every 30s and
  restarts + alerts on any unhealthy service. Previously nothing ever
  called health_check - a dead service thread went unnoticed forever.
- Removed a duplicate start_market_open_poller! definition that Ruby
  was silently preferring; it skipped boot_market_gates! that the
  other (now sole) definition includes.
- safe_stop! now alerts via Telegram with the open-position count
  before stopping services, since after shutdown nothing monitors
  them until restart. Implemented against a pre-existing failing spec
  (daemon_shutdown_spec.rb) rather than writing a new one."
```

---

## Task 2: TickCache TTL-gated memory fast-path

**Files:**
- Modify: `app/services/tick_cache.rb`
- Test: `spec/services/tick_cache_spec.rb` (new — none exists today)

**Interfaces:**
- Consumes: `Live::RedisTickCache.instance` (existing, unchanged).
- Produces: `TickCache.instance.fetch(segment, security_id)` / `.put(tick)` / `.ltp(segment, security_id)` — same public signatures and return shapes as today, with an added `:cached_at` key in the returned hash (additive, not breaking — no caller does strict key-set equality on the result per the codebase grep in the design phase).

- [ ] **Step 1: Write the failing tests**

Create `spec/services/tick_cache_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TickCache do
  let(:cache) { described_class.instance }
  let(:tick) { { segment: 'NSE_FNO', security_id: '12345', ltp: 100.5 } }

  before { cache.clear }

  describe '#fetch memory fast-path' do
    it 'returns the in-memory value without hitting Redis when freshly written' do
      allow(Live::RedisTickCache.instance).to receive(:store_tick)
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick)

      cache.put(tick)
      result = cache.fetch('NSE_FNO', '12345')

      expect(result[:ltp]).to eq(100.5)
      expect(Live::RedisTickCache.instance).not_to have_received(:fetch_tick)
    end

    it 'falls through to Redis once the memory entry is older than the TTL' do
      allow(Live::RedisTickCache.instance).to receive(:store_tick)
      cache.put(tick)

      travel_to(Time.current + described_class::MEMORY_TTL + 0.1) do
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(
          { segment: 'NSE_FNO', security_id: '12345', ltp: 101.0 }
        )

        result = cache.fetch('NSE_FNO', '12345')

        expect(result[:ltp]).to eq(101.0)
        expect(Live::RedisTickCache.instance).to have_received(:fetch_tick)
      end
    end

    it 'hits Redis when nothing is in memory yet' do
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(
        { segment: 'NSE_FNO', security_id: '12345', ltp: 99.0 }
      )

      result = cache.fetch('NSE_FNO', '12345')

      expect(result[:ltp]).to eq(99.0)
      expect(Live::RedisTickCache.instance).to have_received(:fetch_tick)
    end

    it 'returns nil when Redis has nothing and memory is empty' do
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return({})

      expect(cache.fetch('NSE_FNO', '99999')).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/tick_cache_spec.rb`
Expected: FAIL on the first test (`not_to have_received(:fetch_tick)`) — `fetch` currently always calls Redis, the commented-out memory check means it hits `fetch_tick` unconditionally.

- [ ] **Step 3: Implement the TTL-gated memory read in `app/services/tick_cache.rb`**

Add the constant after `include Singleton`:

```ruby
class TickCache
  include Singleton

  MEMORY_TTL = 1.5 # seconds
```

In `put`, tag the merged hash with a timestamp before it's stored (inside the `@map.compute` block, right before the final `new_hash`/`merged` line):

```ruby
      # Restore previous LTP if missing
      new_hash[:ltp] = previous_ltp if new_hash[:ltp].nil? && previous_ltp
      new_hash[:cached_at] = Time.current

      new_hash
    end
```

Replace `fetch`:

```ruby
  # ------------------------
  # FETCH WITH REDIS FALLBACK
  # ------------------------
  def fetch(segment, security_id)
    key = cache_key(segment, security_id)

    mem = @map[key]
    return mem if mem && mem[:cached_at] && (Time.current - mem[:cached_at]) < MEMORY_TTL

    # Then fallback to Redis
    redis_tick = Live::RedisTickCache.instance.fetch_tick(segment, security_id)

    return nil if redis_tick.empty?

    # Hydrate memory so next calls (within MEMORY_TTL) skip Redis
    redis_tick[:cached_at] = Time.current
    @map[key] = redis_tick

    redis_tick
  end
```

- [ ] **Step 4: Run the tick cache spec to verify it passes**

Run: `bundle exec rspec spec/services/tick_cache_spec.rb`
Expected: PASS — all 4 examples green.

- [ ] **Step 5: Run the broader live-services spec suite to catch downstream regressions**

Run: `bundle exec rspec spec/services/live/`
Expected: PASS — nothing consumes the tick hash's exact key set in a way that would break from the added `:cached_at` field (verified via grep in the design phase — only mock-based assertions exist, no strict `eq()` on raw fetched hashes).

- [ ] **Step 6: Commit**

```bash
git add app/services/tick_cache.rb spec/services/tick_cache_spec.rb
git commit -m "Restore TickCache's in-memory fast-path with a TTL gate

fetch() unconditionally hit Redis - the memory check was commented
out. Since web and trading run as separate OS processes sharing only
Postgres/Redis, a blind memory-first read would make the web process
return one stale price forever (it never calls put()). A 1.5s TTL on
the memory entry fixes both: the trading daemon's memory is always
fresh (it just wrote the tick), the web process's hydrated copy ages
out almost immediately and falls through to Redis same as before."
```

---

## Task 3: WS lifecycle hooks + `start!` fall-through bug in `market_feed_hub.rb`

**Files:**
- Modify: `app/services/live/market_feed_hub.rb`
- Test: `spec/services/live/market_feed_hub_spec.rb` (existing — extend it)
- Test: `spec/services/live/market_feed_hub_reconnect_spec.rb` (new)

**Interfaces:**
- Consumes: `DhanHQ::WS::Client#on(:open|:reconnect|:close|:error)`, `#healthy?(stale_after:)` (gem-provided, confirmed present in the installed 3.3.0 gem).
- Produces: `MarketFeedHub#start!` returns `true` only on genuine success, `false` on failure (currently can return `true` after an internal failure — this task fixes that). `#connected?` unchanged. New: `#healthy?` delegates to the gem client where available.

- [ ] **Step 1: Write the failing test for the `start!` fall-through bug**

Add to `spec/services/live/market_feed_hub_spec.rb` (check the file's existing `before` block / mocking conventions first, then match them):

```ruby
  describe '#start! failure handling' do
    it 'returns false and does not report success when the WS client fails to start' do
      hub = described_class.instance
      allow(hub).to receive(:enabled?).and_return(true)
      allow(hub).to receive(:running?).and_return(false)
      allow(hub).to receive(:load_watchlist).and_return([])
      broken_client = instance_double(DhanHQ::WS::Client)
      allow(hub).to receive(:build_client).and_return(broken_client)
      allow(broken_client).to receive(:on)
      allow(broken_client).to receive(:start).and_raise('connection refused')
      allow(hub).to receive(:stop!)

      result = hub.start!

      expect(result).to be false
      expect(hub).to have_received(:stop!)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/live/market_feed_hub_spec.rb -e "does not report success when the WS client fails to start"`
Expected: FAIL — `result` is `true` today because of the fall-through past the `synchronize` block's inner rescue.

- [ ] **Step 3: Fix `start!` in `app/services/live/market_feed_hub.rb`**

Replace the entire method (currently lines 25-78, containing the duplicate `@ws_client = build_client`, the duplicate post-lock `subscribe_watchlist` call, and the fall-through bug):

```ruby
    def start!
      unless enabled?
        Rails.logger.warn('[MarketFeedHub] Not enabled - missing credentials (DHAN_CLIENT_ID/CLIENT_ID or DHAN_ACCESS_TOKEN/ACCESS_TOKEN)')
        return false
      end

      if running?
        Rails.logger.debug('[MarketFeedHub] Already running, skipping start')
        return true
      end

      started = @lock.synchronize do
        next true if running?

        @watchlist = load_watchlist || []
        refresh_watchlist_keys!
        Rails.logger.info("[MarketFeedHub] Loaded watchlist: #{@watchlist.count} instruments")

        @ws_client = build_client
        setup_connection_handlers

        @ws_client.on(:tick) { |tick| handle_tick(tick) }
        @ws_client.on(:reconnect) { |info| handle_reconnect(info) }
        @ws_client.on(:open) { Rails.logger.info('[MarketFeedHub] WebSocket opened') }
        @ws_client.on(:close) { Rails.logger.warn('[MarketFeedHub] WebSocket closed') }
        @ws_client.on(:error) { |e| Rails.logger.error("[MarketFeedHub] WebSocket error: #{e}") }
        @ws_client.start
        Rails.logger.info('[MarketFeedHub] WebSocket client started')

        @running = true
        @started_at = Time.current
        @connection_state = :connecting
        @last_error = nil

        start_watchdog!

        true
      rescue StandardError => e
        Rails.logger.error("Failed to start DhanHQ market feed: #{e.class} - #{e.message}")
        stop!
        false
      end

      return false unless started

      # Subscribe to watchlist OUTSIDE the lock to avoid deadlock
      # (subscribe_many calls ensure_running! which might try to acquire the lock)
      subscribe_watchlist

      Rails.logger.info("[MarketFeedHub] DhanHQ market feed started (watchlist=#{@watchlist.count} instruments)")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to start DhanHQ market feed: #{e.class} - #{e.message}")
      stop!
      false
    end
```

This fixes three things in one pass: the duplicate `@ws_client = build_client` (now called once), the duplicate `subscribe_watchlist` (now called exactly once, only when `started` is true), and the fall-through (an inner failure now sets `started = false`, which the `return false unless started` catches before reaching the "started" log line).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/services/live/market_feed_hub_spec.rb -e "does not report success when the WS client fails to start"`
Expected: PASS.

- [ ] **Step 5: Run the full market_feed_hub spec files to check nothing else broke**

Run: `bundle exec rspec spec/services/live/market_feed_hub_spec.rb spec/services/live/market_feed_hub_integration_spec.rb spec/services/live/market_feed_hub_market_close_spec.rb spec/services/live/market_feed_hub_subscription_spec.rb`
Expected: same baseline as before this task (1 pre-existing unrelated failure: `#handle_tick updates TickCache` calling `TickCache.put` twice — not touched by this task, leave it). No new failures.

- [ ] **Step 6: Write the failing test for `on(:reconnect)` wiring**

Create `spec/services/live/market_feed_hub_reconnect_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  describe '#handle_reconnect' do
    it 'resubscribes active positions immediately on a gem-reported reconnect' do
      hub = described_class.instance
      allow(hub).to receive(:resubscribe_active_positions_after_reconnect)

      hub.send(:handle_reconnect, { attempt: 2, resubscribed: false })

      expect(hub).to have_received(:resubscribe_active_positions_after_reconnect)
    end
  end
end
```

- [ ] **Step 7: Run it to verify it fails**

Run: `bundle exec rspec spec/services/live/market_feed_hub_reconnect_spec.rb`
Expected: FAIL — `handle_reconnect` doesn't exist yet.

- [ ] **Step 8: Add `handle_reconnect` in `app/services/live/market_feed_hub.rb`**

Add near `update_connection_state!` (private section):

```ruby
    def handle_reconnect(info)
      Rails.logger.warn("[MarketFeedHub] WebSocket reconnected (attempt=#{info[:attempt]})")
      resubscribe_active_positions_after_reconnect
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] handle_reconnect failed: #{e.class} - #{e.message}")
    end
```

- [ ] **Step 9: Run it to verify it passes**

Run: `bundle exec rspec spec/services/live/market_feed_hub_reconnect_spec.rb`
Expected: PASS.

- [ ] **Step 10: Add a `healthy?` delegation and remove the stale comment**

Add near `connected?`:

```ruby
    # Delegates to the gem's native health check (frame staleness, not just socket
    # state) where available; falls back to connected? otherwise.
    def healthy?(stale_after: 45)
      return false unless running?
      return false unless @ws_client

      if @ws_client.respond_to?(:healthy?)
        @ws_client.healthy?(stale_after: stale_after)
      else
        connected?
      end
    rescue StandardError
      false
    end
```

Replace the stale comment block in `setup_connection_handlers` (currently claiming "DhanHQ WebSocket client only supports :tick events"):

```ruby
    def setup_connection_handlers
      # Lifecycle hooks (on :tick/:reconnect/:open/:close/:error) are wired directly
      # in start! above. This method is kept as an extension point for any future
      # per-connection setup that needs to run before @ws_client.start.
    end
```

- [ ] **Step 11: Write the failing test for `healthy?`**

Add to `spec/services/live/market_feed_hub_spec.rb`:

```ruby
  describe '#healthy?' do
    it 'delegates to the WS client healthy? when available' do
      hub = described_class.instance
      allow(hub).to receive(:running?).and_return(true)
      client = instance_double(DhanHQ::WS::Client, healthy?: true)
      hub.instance_variable_set(:@ws_client, client)

      expect(hub.healthy?).to be true
      expect(client).to have_received(:healthy?).with(stale_after: 45)
    end

    it 'is false when not running' do
      hub = described_class.instance
      allow(hub).to receive(:running?).and_return(false)

      expect(hub.healthy?).to be false
    end
  end
```

- [ ] **Step 12: Run it to verify it passes**

Run: `bundle exec rspec spec/services/live/market_feed_hub_spec.rb -e "#healthy?"`
Expected: PASS.

- [ ] **Step 13: Run the full set of files touched in this task**

Run: `bundle exec rspec spec/services/live/market_feed_hub_spec.rb spec/services/live/market_feed_hub_integration_spec.rb spec/services/live/market_feed_hub_market_close_spec.rb spec/services/live/market_feed_hub_subscription_spec.rb spec/services/live/market_feed_hub_reconnect_spec.rb`
Expected: PASS except the one pre-existing, unrelated `TickCache.put` double-call failure noted in Step 5.

- [ ] **Step 14: Commit**

```bash
git add app/services/live/market_feed_hub.rb spec/services/live/market_feed_hub_spec.rb spec/services/live/market_feed_hub_reconnect_spec.rb
git commit -m "Wire DhanHQ WS lifecycle hooks, fix start! false-success bug

- start! had a fall-through bug: an inner failure was caught, logged,
  and stop! was called, but execution then fell through duplicate
  'outside the lock' code that still returned true and logged
  success. Also fixed two duplicate calls (build_client, subscribe_
  watchlist) hit along the same success path.
- Wired on(:reconnect) to call resubscribe_active_positions_after_
  reconnect directly instead of inferring reconnection from tick-gap
  timing after the fact. Wired on(:open)/(:close)/(:error) for
  logging.
- Added healthy?(stale_after:), delegating to the gem's native
  frame-staleness check (added in DhanHQ 3.2.0) instead of only ever
  inferring health from time-since-last-tick. Feeds Supervisor's
  health-check watchdog (this sub-project's Task 1) an accurate
  signal for the market_feed service specifically.
- Removed a stale comment claiming the WS client 'only supports
  :tick events' - true in an older gem version, false as of 3.2.0+."
```

---

## Task 4: `ReconciliationService#fix_stuck_exit` — implement against the pre-existing spec

**Files:**
- Modify: `app/services/live/reconciliation_service.rb`
- Test: `spec/services/live/reconciliation_service_stuck_exit_spec.rb` (existing, 3 of 5 examples currently failing — implement against it, don't edit it)

**Interfaces:**
- Consumes: `Rails.application.config.x.trading_supervisor` (may be a plain `Hash` in tests, e.g. `{ exit_manager: exit_engine }`, or a real `TradingSystem::Supervisor` instance in production/other tests — both must resolve `exit_manager` the same way).
- Produces: `fix_stuck_exit(tracker)` — same signature, called from `reconcile_position`. No change to callers.

- [ ] **Step 1: Run the existing spec to confirm the current failure state**

Run: `bundle exec rspec spec/services/live/reconciliation_service_stuck_exit_spec.rb`
Expected: 3 of 5 examples fail:
- Both "when an exit_engine reference is available" examples fail because `.dig(:exit_manager)` doesn't work on a real `TradingSystem::Supervisor` (it only delegates `[]`, not `dig`) — the first example (plain Hash) may or may not fail depending on Hash's `dig` support (Hash does support `dig`, so that one likely fails only via the second issue below, or passes already — verify from the actual output).
- "when no exit_engine reference is available" fails because the current code still calls `tracker.mark_exited!` in that branch, and the double doesn't stub `:meta` (unrelated `NoMethodError` symptom of the same missing-`exit_manager` code path never being hit safely).

- [ ] **Step 2: Fix `fix_stuck_exit` in `app/services/live/reconciliation_service.rb`**

Replace the method (currently at lines 173-188):

```ruby
    def fix_stuck_exit(tracker)
      Rails.logger.warn("[ReconciliationService] Auto-correcting stuck exit for #{tracker.order_no}")

      exit_engine = Rails.application.config.x.trading_supervisor&.[](:exit_manager)

      if exit_engine
        # The engine will check stale_exit_intent? and allow a retry
        exit_engine.execute_exit(tracker, 'AUTO_RECONCILED_EXIT')
      else
        Rails.logger.error("[ReconciliationService] CANNOT confirm broker fill for #{tracker.order_no} - exit_manager unreachable, position stays flagged as stuck")
        Notifications::TelegramNotifier.instance.notify_error(
          "CANNOT confirm broker fill for stuck exit on #{tracker.order_no} - exit_manager unreachable, retrying next cycle",
          context: 'Live::ReconciliationService#fix_stuck_exit'
        )
      end
    rescue StandardError => e
      Rails.logger.error("[ReconciliationService] Failed to auto-correct stuck exit for #{tracker.order_no}: #{e.class} - #{e.message}")
    end
```

Two changes from the original: `.dig(:exit_manager)` → `&.[](:exit_manager)` (works identically on a `Hash` and on `TradingSystem::Supervisor`, which delegates `[]`); the `else` branch no longer calls `tracker.mark_exited!` — it alerts and returns, leaving the tracker untouched so the next 30-second reconciliation cycle retries naturally (per `stuck_in_exit?` still being true).

Also note: the original passed `tracker.meta['exit_reason'] || 'AUTO_RECONCILED_EXIT'` as the reason; the spec expects exactly `'AUTO_RECONCILED_EXIT'` with no `tracker.meta` call (the spec's `tracker` double doesn't stub `:meta`, and it must not receive that message). Drop the `tracker.meta['exit_reason']` lookup — pass the literal string.

- [ ] **Step 3: Run the spec to verify all 5 examples pass**

Run: `bundle exec rspec spec/services/live/reconciliation_service_stuck_exit_spec.rb`
Expected: PASS — all 5 examples green.

- [ ] **Step 4: Run the broader reconciliation and live-services specs**

Run: `bundle exec rspec spec/services/live/reconciliation_service_market_close_spec.rb spec/services/live/`
Expected: PASS except the one already-known pre-existing `market_feed_hub_spec.rb` `TickCache.put` double-call failure (unrelated, tracked separately, not in this plan's scope).

- [ ] **Step 5: Commit**

```bash
git add app/services/live/reconciliation_service.rb
git commit -m "Fix fix_stuck_exit's false-positive close and exit_manager lookup

Two bugs, one method: (1) .dig(:exit_manager) doesn't work on a real
TradingSystem::Supervisor (only [] is delegated, not dig) - switched
to &.[](:exit_manager), which works on both a Hash and Supervisor.
(2) when exit_manager was unreachable, the fallback called
tracker.mark_exited! directly - the DB said closed, the broker was
never asked. Now alerts via Telegram and leaves the tracker stuck-
flagged so the next 30s reconciliation cycle retries once exit_
manager is reachable again. Implemented against a pre-existing
failing spec (reconciliation_service_stuck_exit_spec.rb)."
```

---

## Task 5: Wire `Entries::AdvisoryLock` into `EntryGuard.try_enter`

**Files:**
- Modify: `app/services/entries/entry_guard.rb`
- Test: `spec/services/entries/entry_guard_advisory_lock_spec.rb` (new)

**Interfaces:**
- Consumes: `Entries::AdvisoryLock.with_index_lock(index_key) { ... }` (existing, tested, zero prior callers — see `spec/services/entries/advisory_lock_spec.rb` for its own coverage, not duplicated here).
- Produces: `EntryGuard.try_enter(...)` — same signature, same return value (`true`/`false`), same guard-check ordering. The only observable behavior change: two concurrent calls for the same `index_cfg[:key]` now serialize instead of racing.

- [ ] **Step 1: Write the failing test for lock wiring**

Create `spec/services/entries/entry_guard_advisory_lock_spec.rb`. This mirrors `spec/services/entries/advisory_lock_spec.rb`'s own concurrency test pattern, but drives it through `EntryGuard.try_enter` to prove the lock is actually wrapped around the guard-through-tracker-creation span, not just that the lock mechanism itself works (already covered separately).

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  describe '.try_enter concurrency' do
    it 'serializes two concurrent try_enter calls for the same index key' do
      index_cfg = { key: 'NIFTY', segment: 'NSE_FNO', max_same_side: 1, cooldown_sec: 0 }
      order = Queue.new

      allow(Entries::AdvisoryLock).to receive(:with_index_lock).and_wrap_original do |original, key, &block|
        original.call(key) do
          order << :"#{key}_enter"
          result = block.call
          order << :"#{key}_exit"
          result
        end
      end

      # Block entry immediately after the lock is taken so we don't need to fake
      # the entire guard pipeline - we only care about lock acquisition ordering.
      allow(Risk::CircuitBreaker.instance).to receive(:tripped?) do
        sleep 0.05
        true # blocks every entry, but only AFTER the lock+circuit-breaker-check ran
      end

      t1 = Thread.new do
        described_class.try_enter(index_cfg: index_cfg, pick: { symbol: 'NIFTY24JAN20000CE' }, direction: :bullish)
      end
      sleep 0.01 # ensure t1 enters the lock first
      t2 = Thread.new do
        described_class.try_enter(index_cfg: index_cfg, pick: { symbol: 'NIFTY24JAN20000CE' }, direction: :bullish)
      end
      t1.join
      t2.join

      sequence = []
      sequence << order.pop until order.empty?
      expect(sequence).to eq(%i[NIFTY_enter NIFTY_exit NIFTY_enter NIFTY_exit])
    end
  end
end
```

Note: this test intentionally puts the lock around the circuit-breaker check too (see Step 2 — the lock wraps from the top of `try_enter`'s guard chain), so it can observe ordering without mocking the full guard pipeline down to order placement.

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/entries/entry_guard_advisory_lock_spec.rb`
Expected: FAIL — `Entries::AdvisoryLock.with_index_lock` is never called today (`try_enter` doesn't wrap anything in it), so the `and_wrap_original` spy never fires and `order` stays empty.

- [ ] **Step 3: Wrap `try_enter`'s body in `AdvisoryLock.with_index_lock`**

In `app/services/entries/entry_guard.rb`, `try_enter` currently starts at line 16 with a bare `def try_enter(...)` and its body runs straight through to the `rescue StandardError => e` clause near the end (before the `exposure_ok?` private-ish helper method that follows it in the same `class << self` block). Wrap the entire existing body in the lock:

```ruby
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil)
        Entries::AdvisoryLock.with_index_lock(index_cfg[:key]) do
          Rails.logger.info("[EntryGuard] Attempting entry for #{index_cfg[:key]} (#{direction})")

          # ... existing body, UNCHANGED, from the current "Circuit breaker" check
          # through "!!tracker" ...
        end
      rescue StandardError => e
        signal&.record_entry_outcome('blocked', "exception: #{e.class}")
        bt = e.backtrace&.first(12)&.join("\n")
        msg = "EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}"
        msg = "#{msg}\n#{bt}" if bt.present?
        Rails.logger.error(msg)
        false
      end
```

Concretely: indent the existing method body (everything currently between `Rails.logger.info("[EntryGuard] Attempting entry...")` and `!!tracker`) one level deeper inside a `Entries::AdvisoryLock.with_index_lock(index_cfg[:key]) do ... end` block, and move the existing `rescue StandardError => e` clause to sit at the `def`/`end` level (outside the lock block) rather than inside it — so an exception releases the Postgres advisory lock (the `ensure` inside `AdvisoryLock.with_index_lock` already guarantees `pg_advisory_unlock` runs) before the rescue's logging/return-false runs. Every `return false` / `return true` inside the existing body works unchanged inside the block (Ruby's non-local `return` from a block still returns from the enclosing method, exactly as it already does today from inside the `@lock.synchronize do...end` blocks elsewhere in this codebase — same pattern, already relied upon).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/services/entries/entry_guard_advisory_lock_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the full entry_guard spec suite**

Run: `bundle exec rspec spec/services/entries/entry_guard_spec.rb spec/services/entries/entry_guard_pipeline_spec.rb spec/services/entries/entry_guard_integration_spec.rb spec/services/entries/entry_guard_signal_recording_spec.rb`
Expected: same baseline as before this task (these files had pre-existing unrelated failures from an `entry_guard_pipeline` method-name mismatch, confirmed out of scope during this sub-project's brainstorming — verify no *new* failures were introduced by the lock wrap, i.e., the failure count and specific failing example names match the pre-task baseline).

To get that baseline for comparison if needed: `git stash` any uncommitted change from this task, re-run the same command, note the failures, then `git stash pop` — the diff between the two runs should be zero new failures.

- [ ] **Step 6: Run the advisory lock's own spec to confirm it's unaffected**

Run: `bundle exec rspec spec/services/entries/advisory_lock_spec.rb`
Expected: PASS — unchanged, this task only adds a caller.

- [ ] **Step 7: Commit**

```bash
git add app/services/entries/entry_guard.rb spec/services/entries/entry_guard_advisory_lock_spec.rb
git commit -m "Wire AdvisoryLock into EntryGuard.try_enter, closing a double-entry race

AdvisoryLock.with_index_lock was built specifically to serialize the
guard-pipeline decision + PositionTracker.create! (per its own doc
comment) but had zero callers. try_enter has 7 independent call sites
(strategies/manager.rb, entry_manager.rb, signal/engine.rb x2,
signal/scheduler.rb, bos_entry_engine.rb, agents/trading_orchestrator.rb)
- any two firing near-simultaneously for the same index could both
pass exposure/max-concurrent checks before either committed a
PositionTracker, producing a double entry.

The lock has to span order placement too, not stop before it: the
exposure check's validity must hold continuously through the broker
call, since placing an order that then turns out to violate the
per-index limit is worse than the DB-level race. Only 3 index keys
(NIFTY/BANKNIFTY/SENSEX) ever contend, so holding one pooled Postgres
connection during a broker call is not a real exhaustion risk."
```

---

## Final Verification

- [ ] **Step 1: Run the full set of files touched across all 5 tasks**

Run: `bundle exec rspec lib/trading_system/ app/services/tick_cache.rb app/services/live/market_feed_hub.rb app/services/live/reconciliation_service.rb app/services/entries/entry_guard.rb spec/lib/trading_system/ spec/services/trading_system/ spec/services/tick_cache_spec.rb spec/services/live/market_feed_hub*.rb spec/services/live/reconciliation_service*.rb spec/services/entries/entry_guard*.rb spec/services/entries/advisory_lock_spec.rb`

(Note: this command mixes source and spec paths for convenience of a single readable command — RSpec ignores non-spec files passed to it, so this effectively runs every spec file relevant to this plan in one pass.)

Expected: PASS across all of them, except the two known-and-out-of-scope pre-existing failures noted throughout this plan:
- `market_feed_hub_spec.rb`'s `#handle_tick updates TickCache` (calls `TickCache.put` twice — unrelated test-state issue, not part of this plan's 5 findings)
- Any `entry_guard_pipeline`-related failures already confirmed pre-existing and out of scope during brainstorming

- [ ] **Step 2: RuboCop on every touched file**

Run: `bundle exec rubocop lib/trading_system/daemon.rb lib/trading_system/supervisor.rb app/services/tick_cache.rb app/services/live/market_feed_hub.rb app/services/live/reconciliation_service.rb app/services/entries/entry_guard.rb spec/lib/trading_system/daemon_health_watchdog_spec.rb spec/services/trading_system/supervisor_spec.rb spec/services/tick_cache_spec.rb spec/services/live/market_feed_hub_reconnect_spec.rb spec/services/entries/entry_guard_advisory_lock_spec.rb`

Expected: no new offenses on the lines this plan changed. Pre-existing offenses in untouched parts of these files are out of scope.

- [ ] **Step 3: Confirm no stray debug output or leftover TODOs**

Run: `grep -rn "TODO\|FIXME\|binding.pry\|byebug" lib/trading_system/daemon.rb lib/trading_system/supervisor.rb app/services/tick_cache.rb app/services/live/market_feed_hub.rb app/services/live/reconciliation_service.rb app/services/entries/entry_guard.rb`

Expected: no output.

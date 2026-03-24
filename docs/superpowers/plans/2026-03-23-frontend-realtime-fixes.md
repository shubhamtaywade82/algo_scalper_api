# Frontend Real-Time Update Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the frontend receiving zero live tick-driven updates by switching ActionCable to Redis adapter (cross-process pub/sub), and add circuit breaker push, PnlUpdater health monitoring, stale LTP signalling, and Redis tick TTL.

**Architecture:** Five targeted, independent edits. Fix 1 (cable adapter) is the root cause and must land first — the others are improvements that work only after Fix 1 enables cross-process broadcasts. Backend changes follow TDD with RSpec; frontend changes are verified manually (no frontend test infra exists).

**Tech Stack:** Rails 8, ActionCable, Redis (`redis` gem already in Gemfile), Vue 3 composables, RSpec

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `config/cable.yml` | Modify | Switch dev + prod to Redis adapter |
| `app/services/risk/circuit_breaker.rb` | Modify | Broadcast on trip/reset |
| `app/services/live/pnl_updater_service.rb` | Modify | Health in stats; `pnl_stale` broadcast; `ltp_stale: false` in `pnl_update` |
| `app/controllers/api/dashboard_controller.rb` | Modify | Add `pnl_updater_running` to system hash |
| `app/services/live/redis_tick_cache.rb` | Modify | Add `expire` after `hmset` |
| `dashboard/src/composables/usePositions.js` | Modify | Handle `pnl_stale` message |
| `dashboard/src/composables/useDashboard.js` | Modify | Handle `circuit_breaker` message |
| `spec/services/risk/circuit_breaker_spec.rb` | Create | Tests for ActionCable broadcasts |
| `spec/services/live/redis_tick_cache_spec.rb` | Create | Test for TTL on store_tick |
| `spec/requests/api/dashboard_spec.rb` | Create | Test for pnl_updater_running in response |
| `spec/services/live/pnl_updater_service_spec.rb` | Modify | Add tests for pnl_stale + ltp_stale broadcasts |

---

## Task 1: Switch ActionCable to Redis adapter (root cause)

**Files:**
- Modify: `config/cable.yml`

This is the only change needed for Task 1. No tests — the cable adapter config is validated by running the server and observing live updates work. A wrong value here will fail at boot with a clear error.

- [ ] **Step 1: Replace cable.yml contents**

Open `config/cable.yml`. Replace the entire file with:

```yaml
development:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") %>

test:
  adapter: test

production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") %>
```

The old `solid_cable` block had `connects_to:`, `polling_interval:`, and `message_retention:` stanzas — all of these must be gone. The `cable` database entry in `config/database.yml` is harmless and can stay.

- [ ] **Step 2: Verify Rails boots without error**

```bash
bundle exec rails runner "puts ActionCable.server.config.cable.inspect"
```

Expected output contains `{:adapter=>"redis", :url=>"redis://127.0.0.1:6379/0"}` (or the value of `REDIS_URL` if set).

- [ ] **Step 3: Commit**

```bash
git add config/cable.yml
git commit -m "fix: switch ActionCable to Redis adapter for cross-process broadcasts"
```

---

## Task 2: Circuit breaker immediate push

**Files:**
- Modify: `app/services/risk/circuit_breaker.rb`
- Modify: `dashboard/src/composables/useDashboard.js`
- Create: `spec/services/risk/circuit_breaker_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/services/risk/circuit_breaker_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::CircuitBreaker do
  let(:cb) { described_class.instance }

  before { cb.reset! rescue nil }
  after  { cb.reset! rescue nil }

  describe '#trip!' do
    it 'broadcasts circuit_breaker status to the dashboard channel' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'dashboard',
        hash_including(type: 'circuit_breaker', tripped: true)
      )
      cb.trip!(reason: 'test halt')
    end
  end

  describe '#reset!' do
    before { cb.trip!(reason: 'setup') }

    it 'broadcasts circuit_breaker status to the dashboard channel' do
      # Suppress the trip! broadcast already set up
      allow(ActionCable.server).to receive(:broadcast)

      expect(ActionCable.server).to receive(:broadcast).with(
        'dashboard',
        hash_including(type: 'circuit_breaker', tripped: false)
      )
      cb.reset!
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/services/risk/circuit_breaker_spec.rb --format documentation
```

Expected: 2 failures — "received unexpected arguments" or "expected to receive broadcast but did not".

- [ ] **Step 3: Add broadcasts to circuit_breaker.rb**

Open `app/services/risk/circuit_breaker.rb`.

In `trip!`, after the `Rails.logger.error` line and before `status`, add:

```ruby
current_status = status
ActionCable.server.broadcast('dashboard', { type: 'circuit_breaker' }.merge(current_status))
```

The full `trip!` method should look like:

```ruby
def trip!(reason: nil, ttl: 8.hours)
  payload = { at: Time.current, reason: reason.to_s }
  Rails.cache.write(TRIP_CACHE_KEY, payload, expires_in: ttl)
  Rails.logger.error("[CircuitBreaker] *** TRIPPED *** reason=#{reason.inspect} ttl=#{ttl}")
  current_status = status
  ActionCable.server.broadcast('dashboard', { type: 'circuit_breaker' }.merge(current_status))
  status
rescue StandardError => e
  Rails.logger.error("[CircuitBreaker] trip! failed: #{e.message}")
  raise
end
```

In `reset!`, replace the existing body with:

```ruby
def reset!
  Rails.cache.delete(TRIP_CACHE_KEY)
  Rails.logger.info('[CircuitBreaker] Reset — trading re-enabled')
  current_status = status  # reads fresh: { tripped: false, reason: nil, at: nil }
  ActionCable.server.broadcast('dashboard', { type: 'circuit_breaker' }.merge(current_status))
  true
rescue StandardError => e
  Rails.logger.error("[CircuitBreaker] reset! failed: #{e.message}")
  raise
end
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bundle exec rspec spec/services/risk/circuit_breaker_spec.rb --format documentation
```

Expected: 2 examples, 0 failures.

- [ ] **Step 5: Update useDashboard.js to handle the new message type**

Open `dashboard/src/composables/useDashboard.js`.

In the `received(data)` handler, add a new branch after the `position_exited` branch:

```js
received(data) {
  if (data.type === 'stats') {
    applyData(data)
  } else if (data.type === 'position_activated' || data.type === 'position_exited') {
    onPositionChange?.()
    fetchInitial()
  } else if (data.type === 'circuit_breaker') {
    circuitBreaker.value = { tripped: data.tripped, reason: data.reason, at: data.at }
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add spec/services/risk/circuit_breaker_spec.rb \
        app/services/risk/circuit_breaker.rb \
        dashboard/src/composables/useDashboard.js
git commit -m "feat: broadcast circuit breaker trips/resets immediately via ActionCable"
```

---

## Task 3: PnlUpdater health monitoring

**Files:**
- Modify: `app/services/live/pnl_updater_service.rb`
- Modify: `app/controllers/api/dashboard_controller.rb`
- Create: `spec/requests/api/dashboard_spec.rb`

- [ ] **Step 1: Write failing test for dashboard endpoint**

Create `spec/requests/api/dashboard_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/dashboard', type: :request do
  before do
    allow(Live::PnlUpdaterService.instance).to receive(:running?).and_return(true)
    allow(Live::OrderUpdateHub.instance).to receive(:running?).and_return(false)
    allow(Live::SystemStatusCache.instance).to receive(:all_statuses).and_return(
      ws_market_feed: false, scheduler: 'running'
    )
    allow(Orders).to receive_message_chain(:config, :gateway, :wallet_snapshot).and_return(
      { cash: 100_000, equity: 0, mtm: 0, exposure: 0 }
    )
    allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
      { public_ipv4: '1.2.3.4', public_ipv6: nil, registered_ips: [] }
    )
    # The controller also calls TradingSignal, AlgoConfig, IndexConfigLoader,
    # and Live::TimeRegimeService. Stub these if the test fails with NoMethodError
    # before reaching the pnl_updater_running assertion. For example:
    #   allow(TradingSignal).to receive_message_chain(:order, :limit, :as_json).and_return([])
    #   allow(AlgoConfig).to receive(:fetch).and_return({ risk: {sl_pct: 0.02, tp_pct: 0.04,
    #     hard_rupee_sl: 500, profit_floor: 0.01, trailing: {}}, signals: {enable_adx_filter: true,
    #     adx: {}, enable_direction_gate: false}, trading_time_restrictions: {} })
    #   allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return('regular')
    #   allow(Live::TimeRegimeService.instance).to receive(:regime_config).and_return({})
    #   allow(IndexConfigLoader).to receive(:load_indices).and_return([])
  end

  it 'includes pnl_updater_running in the system hash' do
    get '/api/dashboard'
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['system']['pnl_updater_running']).to eq(true)
  end
end
```

- [ ] **Step 2: Run test — verify it fails**

```bash
bundle exec rspec spec/requests/api/dashboard_spec.rb --format documentation
```

Expected: 1 failure — `pnl_updater_running` key is nil or missing.

- [ ] **Step 3: Add pnl_updater_running to dashboard controller**

Open `app/controllers/api/dashboard_controller.rb`.

Find the `system:` line (currently):

```ruby
system: Live::SystemStatusCache.instance.all_statuses.merge(
  ws_order_update: Live::OrderUpdateHub.instance.running?
),
```

Change it to:

```ruby
system: Live::SystemStatusCache.instance.all_statuses.merge(
  ws_order_update: Live::OrderUpdateHub.instance.running?,
  pnl_updater_running: Live::PnlUpdaterService.instance.running?
),
```

- [ ] **Step 4: Run test — verify it passes**

```bash
bundle exec rspec spec/requests/api/dashboard_spec.rb --format documentation
```

Expected: 1 example, 0 failures.

- [ ] **Step 5: Add pnl_updater_running to PnlUpdaterService stats broadcast**

Open `app/services/live/pnl_updater_service.rb`.

Find `build_dashboard_stats` — the `system:` line inside it (currently):

```ruby
system: Live::SystemStatusCache.instance.all_statuses,
```

Change it to:

```ruby
system: Live::SystemStatusCache.instance.all_statuses.merge(
  pnl_updater_running: running?
),
```

No test needed for this — it is a private method exercised through the existing `flush!`/heartbeat path.

- [ ] **Step 6: Commit**

```bash
git add spec/requests/api/dashboard_spec.rb \
        app/controllers/api/dashboard_controller.rb \
        app/services/live/pnl_updater_service.rb
git commit -m "feat: expose PnlUpdaterService health in dashboard stats and REST API"
```

---

## Task 4: Stale LTP indicator

**Files:**
- Modify: `app/services/live/pnl_updater_service.rb`
- Modify: `dashboard/src/composables/usePositions.js`
- Modify: `spec/services/live/pnl_updater_service_spec.rb`

- [ ] **Step 1: Write failing tests**

Open `spec/services/live/pnl_updater_service_spec.rb`. Append these two new examples after the existing `it` block:

```ruby
describe 'ActionCable broadcasts' do
  let(:tracker) { create(:position_tracker, entry_price: 100.0, quantity: 1, segment: 'NSE_FNO', security_id: '50073') }

  before do
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(service).to receive(:start!).and_return(true)
    # Populate the queue so flush! has an entry to process.
    # The ltp value here doesn't matter — flush! resolves LTP via TickQuery,
    # not from this payload (payload ltp is only a last-resort fallback).
    service.cache_intermediate_pnl(tracker_id: tracker.id, ltp: nil)
  end

  context 'when tick_ltp is nil' do
    before do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
    end

    it 'broadcasts pnl_stale for the tracker' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'positions',
        { type: 'pnl_stale', id: tracker.id }
      )
      service.flush_now!
    end
  end

  context 'when tick_ltp is valid' do
    before do
      allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: 110.0))
      service.cache_intermediate_pnl(tracker_id: tracker.id, ltp: 110.0)
    end

    it 'broadcasts pnl_update with ltp_stale: false' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'positions',
        hash_including(type: 'pnl_update', ltp_stale: false)
      )
      service.flush_now!
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/services/live/pnl_updater_service_spec.rb --format documentation
```

Expected: 2 new failures — broadcasts not sent / wrong payload.

- [ ] **Step 3: Add pnl_stale broadcast in flush!**

Open `app/services/live/pnl_updater_service.rb`.

Find the `unless tick_ltp&.to_f&.positive?` block (around line 204):

```ruby
unless tick_ltp&.to_f&.positive?
  @logger.debug { "[PnlUpdater] Skip #{tracker_id}: no valid LTP (seg=#{seg} sid=#{security_id})" }
  next
end
```

Replace with:

```ruby
unless tick_ltp&.to_f&.positive?
  @logger.debug { "[PnlUpdater] Skip #{tracker_id}: no valid LTP (seg=#{seg} sid=#{security_id})" }
  ActionCable.server.broadcast('positions', { type: 'pnl_stale', id: tracker_id })
  next
end
```

- [ ] **Step 4: Add ltp_stale: false to broadcast_pnl_update**

In the same file, find `broadcast_pnl_update` (around line 399). Replace the `ActionCable.server.broadcast` call:

```ruby
ActionCable.server.broadcast("positions", {
  type: "pnl_update",
  id: tracker_id,
  ltp: ltp_f.round(2),
  pnl: pnl.to_f.round(2),
  pnl_pct: pnl_pct,
  hwm_pnl: hwm.to_f.round(2),
  ltp_stale: false
})
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
bundle exec rspec spec/services/live/pnl_updater_service_spec.rb --format documentation
```

Expected: all examples pass (including the original one).

- [ ] **Step 6: Update usePositions.js to handle pnl_stale**

Open `dashboard/src/composables/usePositions.js`.

In the `received(data)` handler, add a `pnl_stale` branch:

```js
received(data) {
  if (data.type === 'pnl_update') {
    applyPnlUpdate(data)
    markFresh()
  } else if (data.type === 'pnl_stale') {
    const idx = open.value.findIndex(p => p.id === data.id)
    if (idx !== -1) open.value[idx] = { ...open.value[idx], ltp_stale: true }
  }
}
```

When a subsequent `pnl_update` arrives with `ltp_stale: false`, `applyPnlUpdate` spreads the full update object (including `ltp_stale: false`) over the existing position, clearing the flag.

- [ ] **Step 7: Commit**

```bash
git add spec/services/live/pnl_updater_service_spec.rb \
        app/services/live/pnl_updater_service.rb \
        dashboard/src/composables/usePositions.js
git commit -m "feat: broadcast pnl_stale when LTP unavailable; add ltp_stale flag to pnl_update"
```

---

## Task 5: Redis TTL on tick keys

**Files:**
- Modify: `app/services/live/redis_tick_cache.rb`
- Create: `spec/services/live/redis_tick_cache_spec.rb`

- [ ] **Step 1: Write failing test**

Create `spec/services/live/redis_tick_cache_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RedisTickCache do
  let(:cache) { described_class.instance }
  let(:redis_double) { instance_double(Redis) }

  before do
    allow(cache).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:hgetall).and_return({})
    allow(redis_double).to receive(:hmset)
  end

  describe '#store_tick' do
    it 'sets a 1-hour TTL on the tick key after storing' do
      expect(redis_double).to receive(:expire).with('tick:NSE_FNO:50073', 3600)
      cache.store_tick(segment: 'NSE_FNO', security_id: '50073', data: { ltp: 100.0, ts: Time.current.to_i })
    end
  end
end
```

- [ ] **Step 2: Run test — verify it fails**

```bash
bundle exec rspec spec/services/live/redis_tick_cache_spec.rb --format documentation
```

Expected: 1 failure — "expected to receive expire but did not".

- [ ] **Step 3: Add expire call in store_tick**

Open `app/services/live/redis_tick_cache.rb`.

Find the `store_tick` method. After the `hmset` line:

```ruby
args = merged.flat_map { |k, v| [k.to_s, v.to_s] }
redis.hmset(key, *args)
```

Add:

```ruby
redis.expire(key, 3600)
```

The full block should be:

```ruby
args = merged.flat_map { |k, v| [k.to_s, v.to_s] }
redis.hmset(key, *args)
redis.expire(key, 3600)

# return symbolized/casted form for convenience
symbolize_and_cast(merged)
```

- [ ] **Step 4: Run test — verify it passes**

```bash
bundle exec rspec spec/services/live/redis_tick_cache_spec.rb --format documentation
```

Expected: 1 example, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add spec/services/live/redis_tick_cache_spec.rb \
        app/services/live/redis_tick_cache.rb
git commit -m "fix: set 1-hour TTL on Redis tick keys to prevent indefinite persistence"
```

---

## Task 6: Full suite + manual smoke test

- [ ] **Step 1: Run full spec suite**

```bash
bundle exec rspec --format progress
```

Expected: all existing tests pass, no regressions.

- [ ] **Step 2: Manual smoke test**

Start the dev stack:

```bash
./bin/dev
```

Open `http://localhost:3000` (or the dashboard port). Observe:

1. Open positions table updates LTP/PnL values within ~250ms of market ticks (Fix 1 verified)
2. Triggering a circuit breaker trip via `POST /api/circuit_breaker/trip` immediately updates the circuit breaker badge — no page refresh needed (Fix 2 verified)
3. Dashboard system status shows `pnl_updater_running: true` (Fix 3 verified)
4. If DhanHQ feed is disconnected, positions show a stale indicator within 250ms (Fix 4 verified)

- [ ] **Step 3: Final commit (if any cleanup needed)**

```bash
git add -p   # review any remaining unstaged changes
git commit -m "chore: final cleanup after realtime fix implementation"
```

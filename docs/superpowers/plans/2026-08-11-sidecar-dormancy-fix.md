# Sidecar Dormancy Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the node-sidecar from opening any Dhan WebSocket connection (it currently opens two — market and orders — that collide with Rails' own `Live::MarketFeedHub`/`Live::OrderUpdateHub` and cause `429`s on every reconnect), while keeping its Redis-based `dhan:execution:intents`/`fills`/`exits` plumbing intact and dormant for future spread-execution work. Also remove two orphaned Rails ActionCable broadcasts that reference non-existent channels.

**Architecture:** The sidecar's WebSocket usage exists solely to support `PositionMonitor`'s independent exit-trigger and `OrderTracker`'s fill-wait — both dead code paths today because nothing in Rails ever calls `Dhan::SidecarPublisher.publish_intent`. Delete the WS-dependent code (`analytics.ts` entirely; the `client.ws` block in `executor.ts`; the reactive reconnect in `auth.ts`) and leave the Redis intent subscriber untouched.

**Tech Stack:** TypeScript (node-sidecar, ts-node/jest), Ruby/Rails 8 (`Dhan::SidecarListener`).

## Global Constraints

- Do not touch `Entries::EntryGuard`, `Orders::GatewayLive`/`GatewayPaper`, or any live order-placement path — this plan only removes dead WebSocket usage and dead broadcasts.
- Do not change the Redis channel names or payload shapes on `dhan:execution:intents`/`dhan:auth:rotated` — that plumbing stays wired for future use.
- `node-sidecar/src/__tests__/sidecar.test.ts` must still pass unmodified (it only checks `TRADING_MODE` default, unrelated to this change).

---

### Task 1: Delete `analytics.ts` and its call site

**Files:**
- Delete: `node-sidecar/src/analytics.ts`
- Modify: `node-sidecar/src/index.ts:1-27`

**Interfaces:**
- Consumes: none new.
- Produces: `node-sidecar/src/index.ts` no longer imports or calls `startAnalytics`.

- [ ] **Step 1: Confirm no other file imports `analytics.ts`**

Run: `grep -rn "startAnalytics\|from \"./analytics\"\|from './analytics'" node-sidecar/src`
Expected: only `node-sidecar/src/index.ts` (the import and the call) — if anything else matches, stop and report before proceeding.

- [ ] **Step 2: Delete the file**

```bash
rm node-sidecar/src/analytics.ts
```

- [ ] **Step 3: Remove the import and call from `index.ts`**

Current `node-sidecar/src/index.ts`:
```typescript
import dotenv from "dotenv";
import { createDhanClient } from "./auth";
import { startExecutor } from "./executor";
import { startAnalytics } from "./analytics";

dotenv.config();

// Default Node behavior is to crash the process on these, which kills the whole `bin/dev`
// foreman group (any Procfile process exiting triggers SIGTERM to all). This is an auxiliary
// execution/analytics sidecar — it must never take the Rails trading daemon down with it.
process.on("uncaughtException", (e) => console.error("[Sidecar] Uncaught exception:", e));
process.on("unhandledRejection", (e) => console.error("[Sidecar] Unhandled rejection:", e));

async function main() {
  console.log("=================================================");
  console.log("Starting DhanHQ-TS Execution & Analytics Sidecar");
  console.log(`Mode: ${process.env.TRADING_MODE || "paper"}`);
  console.log("=================================================");

  try {
    const client = await createDhanClient();
    await startExecutor(client);
    startAnalytics(client);

    console.log("[Sidecar] Process ready and listening for Rails Redis events.");
  } catch (e) {
    console.error("[Sidecar] Initialization error:", e);
  }
}

main();
```

Replace with:
```typescript
import dotenv from "dotenv";
import { createDhanClient } from "./auth";
import { startExecutor } from "./executor";

dotenv.config();

// Default Node behavior is to crash the process on these, which kills the whole `bin/dev`
// foreman group (any Procfile process exiting triggers SIGTERM to all). This is an auxiliary
// execution sidecar — it must never take the Rails trading daemon down with it.
process.on("uncaughtException", (e) => console.error("[Sidecar] Uncaught exception:", e));
process.on("unhandledRejection", (e) => console.error("[Sidecar] Unhandled rejection:", e));

async function main() {
  console.log("=================================================");
  console.log("Starting DhanHQ-TS Execution Sidecar");
  console.log(`Mode: ${process.env.TRADING_MODE || "paper"}`);
  console.log("=================================================");

  try {
    const client = await createDhanClient();
    await startExecutor(client);

    console.log("[Sidecar] Process ready and listening for Rails Redis events.");
  } catch (e) {
    console.error("[Sidecar] Initialization error:", e);
  }
}

main();
```

- [ ] **Step 4: Type-check**

Run: `cd node-sidecar && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add node-sidecar/src/index.ts
git rm node-sidecar/src/analytics.ts
git commit -m "sidecar: delete dead Greeks-writer analytics module"
```

---

### Task 2: Strip `client.ws` usage from `executor.ts`

**Files:**
- Modify: `node-sidecar/src/executor.ts:1-27`

**Interfaces:**
- Consumes: none new.
- Produces: `startExecutor` no longer references `client.ws`, `tracker` (`OrderTracker`), or `monitor` (`PositionMonitor`) for WebSocket wiring — `OrderTracker`/`PositionMonitor` instances stay (still referenced by `paperEngine`/`liveEngine` constructors below this block) but are never fed live events.

- [ ] **Step 1: Confirm `OrderTracker`/`PositionMonitor` are still needed by the engines below**

Run: `grep -n "tracker\|monitor" node-sidecar/src/executor.ts node-sidecar/src/engines/live.ts node-sidecar/src/engines/paper.ts`
Expected: `tracker` is passed into `new LiveExecutionEngine(client, tracker, monitor)`, `monitor` into both engine constructors — confirms they must still be constructed, just not wired to `client.ws`.

- [ ] **Step 2: Remove the `client.ws` block**

Current lines 19-27 of `node-sidecar/src/executor.ts`:
```typescript
  // Set up WebSocket listeners if available
  if (client.ws) {
    // Unhandled "error" events crash the process (Node EventEmitter default) — reconnects on
    // token rotation (see auth.ts) fire these; must be caught, not left to propagate.
    client.ws.orders?.on("error", (e: any) => console.error("[Executor] Orders WS error:", e));
    client.ws.market?.on("error", (e: any) => console.error("[Executor] Market WS error:", e));
    client.ws.orders?.on("order", (state: any) => tracker.onOrderUpdate(state));
    client.ws.market?.on("tick", (tick: any) => monitor.onTick(tick));
  }

```

Delete this block entirely (lines 19-28, including the trailing blank line before `// Handle position exits emitted by PositionMonitor`).

Resulting `startExecutor` opening (lines 10-19):
```typescript
export async function startExecutor(client: DhanClient): Promise<void> {
  const tracker = new OrderTracker();
  const monitor = new PositionMonitor();
  const skills = createSkillRegistry();

  const isLive = process.env.TRADING_MODE === "live";
  const paperEngine = new PaperExecutionEngine(client, monitor);
  const liveEngine = new LiveExecutionEngine(client, tracker, monitor);

  // Handle position exits emitted by PositionMonitor
```

- [ ] **Step 3: Type-check**

Run: `cd node-sidecar && npx tsc --noEmit`
Expected: no errors (accessing `client.ws` is gone; `tracker`/`monitor` remain used by the engine constructors so no unused-variable errors).

- [ ] **Step 4: Commit**

```bash
git add node-sidecar/src/executor.ts
git commit -m "sidecar: stop opening Dhan market/orders WebSocket — collides with Rails' own feeds"
```

---

### Task 3: Remove the reactive WS reconnect from `auth.ts`

**Files:**
- Modify: `node-sidecar/src/auth.ts:30-42`

**Interfaces:**
- Consumes: none new.
- Produces: `createDhanClient`'s `dhan:auth:rotated` subscriber no longer touches `client.ws` (there's nothing left to reconnect after Task 2).

- [ ] **Step 1: Replace the message handler**

Current lines 30-42 of `node-sidecar/src/auth.ts`:
```typescript
  redisSubscriber.on("message", async (channel) => {
    if (channel === "dhan:auth:rotated") {
      console.log("[Sidecar] Token rotated notification received from Rails. Reconnecting WebSockets...");
      try {
        if (client.ws) {
          await client.ws.disconnect();
          await client.ws.connect();
        }
      } catch (e) {
        console.error("[Sidecar] Failed to reconnect WebSocket after token rotation:", e);
      }
    }
  });

  return client;
```

Replace with:
```typescript
  redisSubscriber.on("message", (channel) => {
    if (channel === "dhan:auth:rotated") {
      console.log("[Sidecar] Token rotated notification received from Rails. tokenProvider will pick up the new token on next use.");
    }
  });

  return client;
```

- [ ] **Step 2: Type-check**

Run: `cd node-sidecar && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Boot the sidecar standalone and confirm zero WS activity**

Run: `cd node-sidecar && REDIS_URL=redis://127.0.0.1:6379/0 TRADING_MODE=paper npx ts-node src/index.ts &` then after a few seconds `kill %1` (or Ctrl-C).
Expected log output: the two startup banner lines, `[Sidecar Executor] Subscribed to dhan:execution:intents`, `[Sidecar] Subscribed to dhan:auth:rotated channel from Token Authority (Rails).`, `[Sidecar] Process ready and listening for Rails Redis events.` — and critically **no** `Market WS error`, **no** `Orders WS error`, **no** `429`. (Requires local Redis running; if Redis isn't available, skip this step's boot and rely on Task 5's full-stack check instead.)

- [ ] **Step 4: Commit**

```bash
git add node-sidecar/src/auth.ts
git commit -m "sidecar: drop WS reconnect-on-token-rotation — no WebSocket left to reconnect"
```

---

### Task 4: Remove orphaned ActionCable broadcasts from `Dhan::SidecarListener`

**Files:**
- Modify: `app/services/dhan/sidecar_listener.rb:48-61`

**Interfaces:**
- Consumes: none new.
- Produces: `process_fill`/`process_exit` still update `PaperPosition`/`PositionTracker` records exactly as before; the existing `PositionTracker::Broadcastable` concern (unrelated to this file, unchanged) continues to broadcast on `positions`/`dashboard` when those records' `update!` calls trip its callbacks. This task only removes the *extra*, currently-dead broadcast calls this file makes directly.

- [ ] **Step 1: Confirm `PositionTracker::Broadcastable` fires on the same `update!` calls this file makes**

Run: `cat app/models/concerns/position_tracker/broadcastable.rb`
Expected: an `after_update` (or equivalent) callback keyed on a status change, broadcasting to `positions`/`dashboard` — confirming the explicit broadcasts in `sidecar_listener.rb` are redundant, not the only path.

- [ ] **Step 2: Edit `process_fill` and `process_exit`**

Current `app/services/dhan/sidecar_listener.rb:48-74`:
```ruby
      def process_fill(payload)
        Rails.logger.info("[SidecarListener] Fill received: #{payload.inspect}")
        return if payload['correlation_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'active', entry_price: payload['fill_price'], quantity: payload['quantity'])
          ActionCable.server.broadcast('paper_positions', paper.as_json) if paper && defined?(ActionCable)
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'open', entry_price: payload['fill_price'], quantity: payload['quantity'])
          ActionCable.server.broadcast("positions_#{tracker.user_id}", tracker.as_json) if tracker.respond_to?(:user_id) && defined?(ActionCable)
        end
      end

      def process_exit(payload)
        Rails.logger.info("[SidecarListener] Exit received: #{payload.inspect}")
        return if payload['correlation_id'].blank? && payload['position_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'])
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'], exit_reason: payload['reason'])
        end
      end
```

Replace with:
```ruby
      def process_fill(payload)
        Rails.logger.info("[SidecarListener] Fill received: #{payload.inspect}")
        return if payload['correlation_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'active', entry_price: payload['fill_price'], quantity: payload['quantity'])
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'open', entry_price: payload['fill_price'], quantity: payload['quantity'])
        end
      end

      def process_exit(payload)
        Rails.logger.info("[SidecarListener] Exit received: #{payload.inspect}")
        return if payload['correlation_id'].blank? && payload['position_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'])
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'], exit_reason: payload['reason'])
        end
      end
```

- [ ] **Step 3: Run rubocop on the file**

Run: `bundle exec rubocop app/services/dhan/sidecar_listener.rb`
Expected: no new offenses.

- [ ] **Step 4: Commit**

```bash
git add app/services/dhan/sidecar_listener.rb
git commit -m "rails: remove SidecarListener broadcasts to channels with no subscriber"
```

---

### Task 5: Full-stack verification

**Files:** none modified — verification only.

- [ ] **Step 1: Run the Rails test suite touching this area**

Run: `bundle exec rspec spec -e "SidecarListener"` (or the equivalent path if a spec file exists — check with `find spec -iname "*sidecar*"` first; if none exists, skip to Step 2, no new spec is required since this task only deletes dead broadcast calls with no prior test coverage).

- [ ] **Step 2: Boot the full stack**

Run: `./bin/dev` (requires Redis + Postgres running per normal dev setup), let it run through at least one `dhan:auth:rotated` cycle if possible (or trigger one manually via `Dhan::TokenManager.refresh!(force: true)` in `bin/rails console` against the running dev DB), watch the `sidecar` process log.

Expected: no `429`, no `Market WS error`, no `Orders WS error` from the sidecar at any point; `trading` process log shows `Live::MarketFeedHub`/`Live::OrderUpdateHub` reconnecting cleanly with no collision-related errors either.

- [ ] **Step 3: Report result to the user**

No commit for this task — it's a verification pass. If Step 2 surfaces a `429` or WS error not attributable to something outside this plan's scope, stop and report before continuing to other plans.

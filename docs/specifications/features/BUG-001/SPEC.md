# BUG-001: Prevent WebSocket Subscription Loss on Hub Restart and False Stale-Tick Pruning

## Overview
Fix two interacting defects in the live WebSocket tick pipeline that cause repeated `[TickQuery] no LTP in cache` and `[RedisTickCache] Pruning ... (stale)` warnings for subscribed option contracts.

## Problem
1. When `Live::MarketFeedHub#restart!` resets the WebSocket client after a tick-feed stall, `stop!` clears `@subscribed_keys` and `@callbacks`, and `start!` only re-subscribes the 4 static watchlist indices. Any option legs subscribed by `Options::ChainWatchService` remain in `@subscribed_legs`, so `resubscribe_legs!` treats them as already subscribed and never re-subscribes them on the new socket. Once `RedisTickCache#prune_stale` removes those keys after 60 seconds, every `ChainWatchService` broadcast loop logs `[TickQuery] no LTP in cache` for all un-resubscribed strikes.
2. `DhanHQ::WS::Decoder` sets `:ts` to the exchange Last Traded Time (`ltt`), whereas `TickCache#put` sets `:cached_at` to the local arrival time of each WebSocket frame. `Live::RedisTickCache#prune_stale` checks `:ts` instead of `:cached_at`, so option contracts with active bid/ask quote updates but no recent trade (`ltt > 60s`) are deleted from Redis every 10 seconds and briefly miss cache until the next quote packet arrives.

## Scope

### In Scope
- Preserve non-watchlist subscriptions and tick callbacks across `Live::MarketFeedHub#restart!` (while keeping `Live::MarketFeedHub#stop!` clearing state on explicit stop).
- Reconcile `Options::ChainWatchService#resubscribe_legs!` against `Live::MarketFeedHub.instance.subscribed?` when the hub is running so legs dropped by an external hub reset are re-subscribed.
- Update `Live::RedisTickCache#prune_stale` to check `:cached_at` first (falling back to `:ts` when `:cached_at` is absent) before pruning a tick as stale.
- Add failing-first regression specs in `spec/services/live/market_feed_hub_reconnect_spec.rb`, `spec/services/options/chain_watch_service_spec.rb`, and `spec/services/live/redis_tick_cache_spec.rb`.

### Out of Scope
- Modifying the external `DhanHQ` gem WebSocket decoder or packet parser.
- Refactoring `MarketFeedHub`, `ChainWatchService`, or `RedisTickCache` beyond the minimal defect fixes.
- Changing `protected_keys_set` or live order execution / gateway logic.

## Acceptance Criteria
- **ACC-001**: When `Live::MarketFeedHub#restart!` restarts a running hub, previously subscribed non-watchlist instruments are re-subscribed via `subscribe_many` and previously registered tick callbacks remain active after `start!` succeeds, while calling `#stop!` directly still clears `@subscribed_keys` and `@callbacks`.
- **ACC-002**: When `Live::MarketFeedHub.instance` is running and reports `subscribed? == false` for a leg already present in `@subscribed_legs`, `Options::ChainWatchService#resubscribe_legs!` includes that leg in `subscribe_many`, while skipping already-subscribed legs and leaving tests with a non-running hub unchanged.
- **ACC-003**: `Live::RedisTickCache#prune_stale` keeps keys whose `cached_at` is within `max_age` seconds even when `ts` (`ltt`) is older than `max_age`, prunes keys whose `cached_at` is older than `max_age`, and falls back to `ts` (or prunes for missing timestamp) when `cached_at` is absent.

# Options Buying: Ingestion Sidecar (Future Reference)

**Status:** Not implemented. **Current approach:** pure Ruby stream hybrid inside `trading:daemon`.

This document captures when and how a Node.js/Go ingestion sidecar might be added — without duplicating execution or strategy logic in another language.

---

## When to Consider a Sidecar

Pull the trigger only if measured guardrails break on the trading host:

| Metric | Stay on Ruby | Consider sidecar |
|--------|--------------|------------------|
| Concurrent option SIDs (full mode) | ≤ 15 | > 15 across indices |
| Ingestion rate | ≤ 1,500 ticks/s | > 5,000 ticks/s sustained |
| Trading daemon CPU | < 40% of one core | Pegged during unpack |
| Internal lag (WS → Redis) | ≤ 5 ms p95 | > 15 ms p95 |

Until then, Ruby + Redis Streams inside `MarketFeedHub` callbacks is sufficient.

---

## What the Sidecar Would Do (Ingestion Only)

```
[DhanHQ WS] → [Node/Go sidecar: binary unpack + filter] → [Redis Stream XADD]
                                                              ↓
                                                    [Ruby StreamConsumer]
                                                              ↓
                                                    [EntryGuard → Placer]
```

**In scope for sidecar:**

* WebSocket connection and binary frame parsing
* Strike filtering (radar list from Redis)
* `XADD` with `MAXLEN ~1000`
* Optional `HSET` cache snapshot

**Out of scope (stays Ruby):**

* `Signal::Engine`, guard pipeline, risk manager
* `Orders::Placer`, position lifecycle, exit engine
* Dhan error mapping (`DH-904`, etc.)
* Broker order placement

---

## Why Not Now

1. **Duplicate feed risk** — a sidecar WS alongside `MarketFeedHub` splits truth and reconnect logic.
2. **Integration tax** — dual deploy, schema sync, cross-language debugging.
3. **Latency** — extra hop is negligible vs Dhan REST RTT (~40–120 ms); internal Ruby path is already sub-5 ms for `XADD`.
4. **Native gem** — `dhanhq-client` unpack + models already live in Ruby.

---

## Migration Path (If Needed)

1. Sidecar writes to the **same** Redis keys (`options_buying:stream:{sid}`).
2. Disable `StreamWriter#xadd` in Ruby (config flag); keep `StreamConsumer` unchanged.
3. **Do not** remove `MarketFeedHub` until index/position ticks are fully covered by sidecar subscriptions.
4. Execution path unchanged — still `breakout_ready` → `EntryGuard`.

---

## GC / Ops Hardening (Ruby Path)

Optional for long-running `trading:daemon`:

```bash
export RUBY_GC_HEAP_GROWTH_FACTOR=1.1
export RUBY_GC_MALLOC_LIMIT=64000000
export RUBY_GC_OLDMALLOC_LIMIT=64000000
```

Keep tick handlers thin: `XADD` + `HSET` only; no indicator math on the hot path.

---

## Related

* [options_buying_stream_architecture.md](options_buying_stream_architecture.md) — current hybrid implementation
* [options_buying_framework.md](options_buying_framework.md) — trading rules

# Broker contract: what is verified and what is not

Every DhanHQ wire touchpoint the live path depends on, and the evidence for each. This is the list to re-check before
any live change, and the first thing to update when a sandbox recording comes back.

Evidence levels:

- **Typed**: `@nemesis-oss/dhanhq-sdk` 2.0.1 declares the field or enum. `npm run typecheck` fails if the code diverges.
- **SDK-read**: the SDK's runtime behaviour was read in its `dist/index.cjs` on 2026-11-03. It is not a broker fact.
- **Assumed**: the code depends on it at runtime. Nothing in this repository shows the broker behaves this way.
- **Recorded**: a sandbox exchange checked into `docs/` shows it. **None yet.**

## 1. Trading writes

| # | Touchpoint | Code | Evidence | Note |
| --- | --- | --- | --- | --- |
| 1.1 | Super-order entry: `superOrders.place`, LIMIT at `entryReference`, `targetPrice`, `stopLossPrice`, `productType: INTRADAY` | `src/dhan/liveExecution.ts` `submitEntry` | Typed | The LIMIT is the only price guard. A fill above it cannot happen, so the sized risk holds. |
| 1.2 | `correlationId` at most 30 characters | `src/execution/brokerIds.ts` | Assumed | The comment cites Dhan's OpenAPI. That source was not re-read here. Ids are at most 13 characters, so the limit is not reached in practice. |
| 1.3 | Exit SELL: `orders.place`, `MARKET`, `INTRADAY`, `DAY`, quantity capped at broker net long | `submitExit` | Typed | Quantity cap is enforced in code. |
| 1.4 | Cancel one bracket leg: `superOrders.cancel({ orderId, orderLeg })`, `orderLeg` is `ENTRY_LEG`, `STOP_LOSS_LEG` or `TARGET_LEG` | `cancelBracketLegs`, `submitEntry` timeout | Typed (enum); Assumed (effect) | Typed means the names are right. That an accepted cancel leads to a CANCELLED leg in the book is assumed. |
| 1.5 | Kill switch: `traderControls.setKillSwitch('ACTIVATE')`, then read-back `getKillSwitchStatus().killSwitchStatus` | `engageBrokerKillSwitch` | Typed; Assumed (effect) | Typed fields. Dhan refusing activation while a position or order is open is recorded in `ARCHITECTURE.md` but not re-verified. |
| 1.6 | Exit SELL that rests unfilled: `orders.cancel(orderId)` at the order timeout, then the final status is awaited | `settleUnfilledExit` | Typed (call); Assumed (effect) | Dhan states that an API `MARKET` order is converted to a LIMIT with market price protection, so 1.3 is not an immediate fill. The band is not documented in the SDK. A cancel with no fill is reported as rejected and the exit is retried; a failed cancel leaves the outcome unknown until 1.6a settles it. |
| 1.6a | A SELL with no known outcome: `orders.getByCorrelationId` on each reconciliation pass, and `orders.cancel` again while the order rests | `settleUnknownExit` | Typed (call); **Assumed** (fields) | Relies on `orderStatus` and `filledQty` in the order row. `CANCELLED`, `REJECTED` or `EXPIRED` with `filledQty` exactly 0 is read as definitive, and the exit is released for a retry. A row that cannot be read, has no status, or shows any fill leaves the outcome unknown and no SELL is sent. Whether a SELL placed with a timed-out response is findable by correlation id is not recorded. |
| 1.7 | `trailingJump` on the super order | `submitEntry` | **Assumed** | Sent when `TRAILING_JUMP_PCT` is above zero. The broker trails the stop leg by its own rule. The agent's `calculateTrailingStop` is a different model, so on the live venue its stop is an estimate for the cockpit and the journal. The day book's open risk stays at the initial stop there, because the broker's leg only ever moves up from it. The broker's trigger rule is not verified. |
| 1.8 | Order APIs are accepted only from a static IP registered with Dhan | every broker write | **Assumed (operational)** | Required for retail API orders since 2026-04-01. An unregistered IP is refused with `DH-905`, which is a definitive rejection here. Register the host's IP before a sandbox or live run. |
| 1.9 | Broker P&L exit: `traderControls.setPnlExit({ lossValue, enableKillSwitch: false, productType: ['INTRADAY'] })`, once at start, live only, when `BROKER_PNL_EXIT` is on | `armBrokerPnlExit`, `tryArmPnlExit` in `src/dhan/liveExecution.ts` | Typed (fields); **Assumed** (sign and units of `lossValue`, what the broker does when the rule fires, whether it persists across sessions) | Classified as a placement. A 4xx except 401, 408 and 429 was not applied, and the next entry tries once more. Anything else is never resent, and entries are refused as unconfirmed. The SDK's sandbox allow-list has no `/pnlExit`, so sandbox refuses the call before any request (`SandboxUnsupportedError`). `getPnlExit()` reads the rule back; the adapter does not call it. |

## 2. Reads the live path relies on

| # | Touchpoint | Fields used | Evidence | Note |
| --- | --- | --- | --- | --- |
| 2.1 | `superOrders.list()` row | `orderId`, `orderStatus`, `correlationId` | Typed (as optional) | The SDK types the row as `{ orderId, orderStatus?, correlationId?, [key]: unknown }`. |
| 2.2 | Super-order row `legDetails[]` | `legName`, `orderStatus` | **Assumed** | Not typed: it falls under the index signature. The adapter's reading of it is the basis for exit safety (`liveBracketLegs`). A missing or unreadable `legDetails` counts as **live**, so the failure direction is "refuse to exit", not "send a SELL". |
| 2.3 | Settled order statuses | `CANCELLED`, `TRADED`, `REJECTED`, `EXPIRED`, `CLOSED` | Assumed | One shared constant (`TERMINAL_ORDER_STATUSES`) for the adapter and the restart guard. Any other status counts as live. `PART_TRADED`, `TRIGGERED`, `PENDING` and `TRANSIT` are non-terminal here. |
| 2.4 | `positions.list()` row | `netQty`, `productType`, `securityId`, `exchangeSegment`, `dayBuyQty`, `dayBuyValue`, `daySellQty`, `daySellValue` | Typed (fields); Assumed (semantics) | `fillSince` assumes the day totals are per instrument and per product, summed over the day. A same-day round trip in one contract is why a baseline is taken before each entry. |
| 2.4a | A held position that has no row in `positions.list()` | `brokerPosition`, `reconcile` | **Assumed** | Read as unknown, not flat. The exit path retries the read three times and then reports the exit unconfirmed with the legs untouched. Once the legs are confirmed cancelled, a failed read sends nothing and is reported as rejected, so the agent retries the exit instead of halting with no stop. Reconciliation books a close only after three consecutive reads without the row. Whether Dhan ever omits a row for a position opened today is not recorded. |
| 2.4b | Terminal market-feed disconnect: reason codes 804 to 810 | `DhanFeed.handleDisconnect`, `TERMINAL_FEED_DISCONNECT_CODES`, `entryBlockReason` | **Assumed** (codes), Typed (event) | SDK 2.1.0 halts the market socket on these codes and emits only `disconnect`; SDK 2.0.1 reconnects forever. Our policy is the same on both: record the stop, refuse entries, alert (`feed_terminal`). Exits keep the broker's legs and the clock. The code list is copied from the SDK's `FEED_TERMINAL_DISCONNECT_CODES`; a sandbox run that sees a terminal code is not on record. |
| 2.5 | Order-update stream | `OrderState` via the SDK's `OrderTracker` | Typed (SDK-owned) | Fills are confirmed only from this stream, never from the HTTP response (the adapter header, and `ARCHITECTURE.md` invariant 5). |

## 3. How a placement failure is classified

`classifyPlacementError` decides whether a failed write may have reached the venue. A definitive rejection leaves the
position as it was. Anything else halts the underlying until the order is resolved.

| Error | Verdict | Why | Evidence |
| --- | --- | --- | --- |
| `ValidationError` (SDK schema check, before any request) | REJECTED | Never sent | SDK-read: thrown before `httpClient.request` |
| `ApiResponseError` 4xx except 401, 408, 429 | REJECTED | Assumed to be a definitive refusal | **Assumed.** This is the claim most in need of a recording: a 4xx that also left the order live would be a double-trade risk |
| `ApiResponseError` 401 | UNCONFIRMED | SDK refuses to resend a write after an auth failure | SDK-read: `rejectUnreplayableAfterAuthFailure` |
| 408, 429, 5xx, network timeout | UNCONFIRMED | May have been sent | SDK-read: no retry for non-GET writes |
| `CircuitOpenError` | UNCONFIRMED | Thrown before any request is sent, so the classifier is over-cautious | SDK-read: the breaker wraps every request, writes included. Halting is the safe direction, so the classification is left as is |

## 4. What the SDK does on its own

- Automatic retry happens only for `GET` requests marked `safeToRetry`. Every trading write is not retried on transport
  errors (SDK-read). Only option-chain reads are marked `safeToRetry` in 2.0.1.
- Rate limiter and circuit breaker wrap all requests, writes included (SDK-read). A write can queue behind the limiter.
  Latency is not part of the contract above.

## 5. What is not verified, and what would verify it

Nothing in this table has been seen against the live Dhan API from this environment. There are no broker credentials
here, and this change does not reach Dhan.

| Open question | Verified by |
| --- | --- |
| 2.2: the `legDetails` shape and the leg `orderStatus` values | `npm run smoke:trade` against the sandbox, with the wire recorder writing to `docs/sandbox/` (the roadmap's OTA-106) |
| 1.4: an accepted leg cancel reads CANCELLED in the book | Same recording |
| Section 3: a 4xx write is never live at the venue | Sandbox: a deliberately invalid order, then a book read |
| 2.3: the settled-status set is complete | Sandbox: an order cancelled, rejected and expired, each recorded |
| 1.9: the sign and units of `lossValue`, the broker's action when the rule fires, and whether it persists across sessions | An operator check on the live account, because the SDK refuses this call in sandbox: read `getPnlExit()` before and after arming, and record both responses |

Until a recording exists, the fake broker in `tests/liveExecution.test.ts` is the only definition of these shapes. Changing
a fake response changes the contract, so it needs a recording to justify it.

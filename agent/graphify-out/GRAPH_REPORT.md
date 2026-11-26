# Graph Report - options-trading-agent  (2026-11-09)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 2006 nodes · 5978 edges · 88 communities (84 shown, 4 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 171 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `76c66e79`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87

## God Nodes (most connected - your core abstractions)
1. `istParts()` - 84 edges
2. `UnderlyingAgent` - 76 edges
3. `Candle` - 56 edges
4. `Orchestrator` - 47 edges
5. `istEpoch()` - 46 edges
6. `loadConfig()` - 44 edges
7. `compose()` - 43 edges
8. `DayBook` - 37 edges
9. `Logger` - 32 edges
10. `IstParts` - 32 edges

## Surprising Connections (you probably didn't know these)
- `client()` --calls--> `PaperExchangeClient`  [EXTRACTED]
  tests/paperExchange.test.ts → src/paper/exchangeClient.ts
- `Path` --references--> `Candle`  [EXTRACTED]
  tests/trail.test.ts → src/domain/types.ts
- `chargesFor()` --calls--> `roundTripChargesInr()`  [EXTRACTED]
  tests/paperVenue.test.ts → src/options/pricing.ts
- `withTerminal()` --indirect_call--> `App()`  [INFERRED]
  tests/cockpitApp.test.ts → src/ui/App.tsx
- `build()` --calls--> `Orchestrator`  [EXTRACTED]
  tests/runtime.test.ts → src/runtime/orchestrator.ts

## Import Cycles
- None detected.

## Communities (88 total, 4 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (86): string-width@^7.2.0, chalk, string-width, LogRecord, PositionView, formatMinuteOfDay(), isMarketSessionOpen(), analysisReadings() (+78 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (20): OptionType, PositionRow, bookUnresolved(), IntentFields, isPositiveFinite(), PendingIntent, restoreDayBook(), RestoreResult (+12 more)

### Community 2 - "Community 2"
Cohesion: 0.06
Nodes (12): OpenPosition, ExecutionEvent, AdvisorChatClient, EntrySnapshot, CandleBuilder, SerialQueue, describe(), instrumentRefOf() (+4 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (35): auditClosedPosition(), auditLedgerChain(), auditOrders(), auditPositions(), auditSinglePosition(), AuditSummary, buildSummary(), expectedEntryDelta() (+27 more)

### Community 4 - "Community 4"
Cohesion: 0.10
Nodes (43): argument(), cellReport(), costsArgument(), dateArgument(), fetchDataset(), flag(), installedSdkVersion(), main() (+35 more)

### Community 5 - "Community 5"
Cohesion: 0.09
Nodes (27): BracketLeg, DayTotals, NO_DAY_TOTALS, PositionRow, SuperOrderRow, TERMINAL_ORDER_STATUSES, ExitReason, OptionContract (+19 more)

### Community 6 - "Community 6"
Cohesion: 0.09
Nodes (19): classifyPlacementError(), dayTotals(), describeError(), entrySettledInBook(), fillSince(), liveBracketLegs(), LiveClient, LiveExecutionPort (+11 more)

### Community 7 - "Community 7"
Cohesion: 0.10
Nodes (41): CellOptions, cellValues(), contextCells(), DayTags, groupCells(), judgeCell(), bestSessionShare(), bootstrapMeanR() (+33 more)

### Community 8 - "Community 8"
Cohesion: 0.12
Nodes (37): argument(), evidenceIdsPresent(), main(), priorVariants(), base, DOCUMENTED_EVIDENCE, DocumentedEvidence, NO_PROVENANCE (+29 more)

### Community 9 - "Community 9"
Cohesion: 0.09
Nodes (38): argument(), cell(), dayArgument(), HEADER, journalDays(), main(), printReport(), row() (+30 more)

### Community 10 - "Community 10"
Cohesion: 0.10
Nodes (35): analyzeOptionChain(), analyzePcr(), calculateStraddle(), ChainAnalysis, checkOptionBuyingConfluence(), computeSentiment(), ConfluenceCheckResult, findOiWalls() (+27 more)

### Community 11 - "Community 11"
Cohesion: 0.09
Nodes (17): TRADING_MODES, TradingMode, EventLog, EventLogOptions, LedgerWriter, backfillDay(), BackfillReport, parseJournal() (+9 more)

### Community 12 - "Community 12"
Cohesion: 0.12
Nodes (35): ALL_IN_LIVE_ACK_PHRASE, DhanAuthConfig, Env, flag(), hostOfUrl(), KNOWN_UNDERLYINGS, LIVE_ACK_PHRASE, loadConfig() (+27 more)

### Community 13 - "Community 13"
Cohesion: 0.10
Nodes (18): AgentConfig, LiveExecutionOptions, instrumentKey(), OptionSegment, UnderlyingSpec, GatewayPortOptions, PostgresPaperOptions, TradeAdvisor (+10 more)

### Community 14 - "Community 14"
Cohesion: 0.11
Nodes (15): ioredis, configFingerprint(), CacheStore, MemoryCacheStore, msUntilNextIstMidnight(), RedisCacheStore, MemoryRateGate, MemoryRateGateOptions (+7 more)

### Community 15 - "Community 15"
Cohesion: 0.10
Nodes (19): pg, LeaseLostError, LeaseLostListener, LeaseOptions, PostgresLeaseStore, MIGRATIONS, assertOrdered(), migrate() (+11 more)

### Community 16 - "Community 16"
Cohesion: 0.06
Nodes (31): POSTGRES_PASSWORD, POSTGRES_USER, TEST_DATABASE_URL, TEST_REDIS_URL, jobs, verify, name, on (+23 more)

### Community 17 - "Community 17"
Cohesion: 0.17
Nodes (20): clock(), findMultiSignal(), PARAMS, walk(), line(), trade(), clock(), PARAMS (+12 more)

### Community 18 - "Community 18"
Cohesion: 0.14
Nodes (28): activationR(), atrLevel(), evaluateLeg(), ExitIntent, firstIndexAtOrAfter(), lastAtr(), LegResult, legsOf() (+20 more)

### Community 19 - "Community 19"
Cohesion: 0.17
Nodes (29): argument(), contextCellsFor(), coupledCheck(), fineCheck(), formatRows(), loadEntries(), main(), minimumDetectable() (+21 more)

### Community 20 - "Community 20"
Cohesion: 0.09
Nodes (8): TrackedPosition, InstrumentRef, Runtime, OrchestratorFeed, FeedPort, FakeFeed, FAKE_SPEC, QuietFeed

### Community 21 - "Community 21"
Cohesion: 0.11
Nodes (23): TradeState, OptionQuote, BracketLevels, SizingResult, adverseCostsFor(), buildEntrySnapshot(), EntryPrices, EntrySnapshotInput (+15 more)

### Community 22 - "Community 22"
Cohesion: 0.09
Nodes (22): ADVISORY_SCHEMA, AdvisoryDecision, AdvisoryVerdict, SYSTEM_PROMPT, breakoutWithoutSettling(), build(), CE, chain() (+14 more)

### Community 23 - "Community 23"
Cohesion: 0.11
Nodes (19): describeAdvisorError(), OllamaTradeAdvisor, ChainRecorder, RunScope, scopeJournalLines(), assertInrAccount(), buildAdvisor(), buildGateway() (+11 more)

### Community 24 - "Community 24"
Cohesion: 0.20
Nodes (26): ema(), superTrend(), closeCross(), confluenceAgrees(), evaluateOrbSupertrend(), openingRangeCross(), openingRangeWindow(), prepareBreak() (+18 more)

### Community 25 - "Community 25"
Cohesion: 0.07
Nodes (28): scripts, build, check, cockpit:demo, db:acknowledge, db:migrate, db:reset-wallet, db:status (+20 more)

### Community 26 - "Community 26"
Cohesion: 0.12
Nodes (25): CheckInput, Loaded, TrailSpec, ResearchDataset, ResearchSession, ReplayConfig, aggregate(), aggregateDataset() (+17 more)

### Community 27 - "Community 27"
Cohesion: 0.15
Nodes (18): RFC-4648, RFC-6238, SandboxConfig, assertUsableToken(), BROKER_ERROR_KEYS, clarifyDhanLoginFailure(), createTotpProvider(), formatExpiry() (+10 more)

### Community 28 - "Community 28"
Cohesion: 0.15
Nodes (21): main(), printResetSummary(), resetDatabaseState(), resetJournalFile(), ResetStats, argument(), assertAgentStopped(), assertSameCadence() (+13 more)

### Community 29 - "Community 29"
Cohesion: 0.17
Nodes (18): Direction, DayState, HeldPosition, PendingEntry, ReplayResult, TradeContext, tradeContext(), ExpiryBucket (+10 more)

### Community 30 - "Community 30"
Cohesion: 0.14
Nodes (24): TrailPosition, TrailState, legBars(), strikeKey(), applyTrail(), ReplayExitReason, advance(), AdvanceInput (+16 more)

### Community 31 - "Community 31"
Cohesion: 0.15
Nodes (18): adaptiveSuperTrend(), BandState, BandStep, calculateSuperTrend(), efficiencyRatio(), stepBands(), SuperTrendState, SuperTrendTrend (+10 more)

### Community 32 - "Community 32"
Cohesion: 0.14
Nodes (20): Cell, SeededRng, Interval, resampleDays(), bestPolicy(), Fold, mean(), monthOf() (+12 more)

### Community 33 - "Community 33"
Cohesion: 0.20
Nodes (20): assertTick(), bracketLevels(), calculateTrailingStop(), decimalPlaces(), EXCHANGE_TXN_PCT, expirySettlementPrice(), roundDownToTick(), roundTripChargesInr() (+12 more)

### Community 34 - "Community 34"
Cohesion: 0.13
Nodes (4): Lease, LeaseStore, MemoryLeaseStore, fixture()

### Community 35 - "Community 35"
Cohesion: 0.12
Nodes (21): description, devDependencies, ts-language-mcp@2.3.1, tsx@^4.19.0, @types/node@^22.0.0, @types/pg@^8.23.1, @types/react@^18.3.31, typescript@^5.9.3 (+13 more)

### Community 36 - "Community 36"
Cohesion: 0.18
Nodes (11): dotenv, argument(), main(), argument(), main(), PostgresLedger, stripNul(), createPostgresPool() (+3 more)

### Community 37 - "Community 37"
Cohesion: 0.16
Nodes (13): asArray(), asRecord(), errorText(), isDefinitiveRefusal(), KNOWN_STATUSES, networkMessage(), PaperExchangeClient, PaperExchangeClientOptions (+5 more)

### Community 38 - "Community 38"
Cohesion: 0.11
Nodes (20): interval, retries, test, timeout, environment, healthcheck, image, ports (+12 more)

### Community 39 - "Community 39"
Cohesion: 0.15
Nodes (17): @nemesis-oss/dhanhq-sdk, CONTRACT, CONTRACT_LIST, normalizeExpiry(), positiveNumber(), toOptionContract(), INTRADAY_INTERVALS, IntradayInterval (+9 more)

### Community 40 - "Community 40"
Cohesion: 0.18
Nodes (6): check(), main(), MarketContext, InstrumentMaster, InstrumentSource, DhanMarketData

### Community 41 - "Community 41"
Cohesion: 0.17
Nodes (12): describe(), DhanSandboxGateway, fillOutcome(), SandboxClient, SandboxGatewayOptions, TERMINAL_UNFILLED, GatewayOrder, gateway() (+4 more)

### Community 42 - "Community 42"
Cohesion: 0.18
Nodes (9): main(), WAIT_MS, asPriceEvent(), DhanFeed, DhanFeedOptions, DhanMarketFeedMode, FeedClient, PriceEvent (+1 more)

### Community 43 - "Community 43"
Cohesion: 0.18
Nodes (6): Candle, Signal, BarSeries, EntryObserver, OrbSupertrendParams, StrategySession

### Community 44 - "Community 44"
Cohesion: 0.16
Nodes (14): ALERT_EVENT_TYPES, ALERT_ICONS, AlertListener, alertText(), AlertTransports, buildAlertListener(), createAlertSink(), createTelegramAlertSink() (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.11
Nodes (18): compilerOptions, esModuleInterop, exactOptionalPropertyTypes, isolatedModules, jsx, lib, module, moduleResolution (+10 more)

### Community 46 - "Community 46"
Cohesion: 0.29
Nodes (12): Check, assertWarmupClock(), previousDayBreak(), previousDayLevels(), IST_OFFSET_MS, IstParts, istParts(), NSE_SESSION_CLOSE_MINUTE (+4 more)

### Community 47 - "Community 47"
Cohesion: 0.24
Nodes (16): fetchChainWithRetry(), main(), record(), reportSummary(), resolveMarket(), results, runRiskCheck(), StepResult (+8 more)

### Community 48 - "Community 48"
Cohesion: 0.21
Nodes (14): main(), restoreScreen(), buildRuntime(), OPERATOR_INTERRUPT_ARM_MS, operatorInterrupt(), resetOperatorInterrupt(), StopKind, Action (+6 more)

### Community 49 - "Community 49"
Cohesion: 0.20
Nodes (16): AddViolation, checkAccountLimits(), checkDataFreshness(), checkOrderPricing(), checkOrderSizing(), checkPositionLimits(), checkTimingLimits(), evaluatePreTrade() (+8 more)

### Community 50 - "Community 50"
Cohesion: 0.14
Nodes (12): ADR-0001, ADR-0012, filesUnder(), relPath(), sourceFiles(), SRC, VENUE_ADAPTERS, read() (+4 more)

### Community 51 - "Community 51"
Cohesion: 0.16
Nodes (5): FakeStdin, FakeStdout, plain(), wait(), withTerminal()

### Community 52 - "Community 52"
Cohesion: 0.16
Nodes (8): IllegalTransitionError, TRADE_EVENTS, TRADE_STATES, TradeEvent, TradeStateMachine, TransitionRecord, TRANSITIONS, TransitionTable

### Community 53 - "Community 53"
Cohesion: 0.18
Nodes (16): CostModel, BootstrapResult, PathSimulation, SampleSummary, CostStressRun, DataQuality, dataQuality(), DEFAULT_TIME_MACHINE_OPTIONS (+8 more)

### Community 54 - "Community 54"
Cohesion: 0.22
Nodes (10): argument(), main(), journalFileName(), joinShadow(), mean(), ShadowEntry, ShadowJournalError, ShadowPair (+2 more)

### Community 55 - "Community 55"
Cohesion: 0.21
Nodes (4): describe(), GatewayExecutionPort, OrderGateway, port()

### Community 56 - "Community 56"
Cohesion: 0.19
Nodes (5): PaperOrder, parseOrder(), chargesOf(), PaperExchangeGateway, PaperExchangeGatewayOptions

### Community 57 - "Community 57"
Cohesion: 0.14
Nodes (14): dependencies, chalk@^5.6.2, cli-truncate@^4.0.0, dotenv@^16.4.5, ioredis@^6.0.0, @nemesis-oss/dhanhq-sdk@2.0.1, @nemesis-oss/tg-format@^0.1.0, pg@^8.23.1 (+6 more)

### Community 58 - "Community 58"
Cohesion: 0.18
Nodes (7): recordWireCalls(), redact(), WireOutcome, WireRecord, WireSink, Client, Orders

### Community 59 - "Community 59"
Cohesion: 0.18
Nodes (5): GatewayOutcome, NOW, OPTION, ScriptedGateway, SILENT

### Community 60 - "Community 60"
Cohesion: 0.21
Nodes (10): correlationIdFor(), SelectionInput, option(), SILENT, uniqueId(), chainWith(), CONTRACTS, input() (+2 more)

### Community 61 - "Community 61"
Cohesion: 0.17
Nodes (11): chain_analysis, enabled, min_headroom_pts, context, enabled, structure_exit, mode, paper (+3 more)

### Community 62 - "Community 62"
Cohesion: 0.29
Nodes (5): debitWallet(), insertOrder(), PostgresPaperStore, LedgerFence, runFenced()

### Community 63 - "Community 63"
Cohesion: 0.20
Nodes (7): onTouch(), OPEN_TRAIL, TrailSeries, BOTH, STUDY_GRID, Path, runPath()

### Community 65 - "Community 65"
Cohesion: 0.33
Nodes (3): testExecution(), PaperExecutionPort, collect()

### Community 66 - "Community 66"
Cohesion: 0.29
Nodes (7): PortfolioResult, PortfolioRules, PortfolioTrade, refusalFor(), simulatePortfolio(), ReplayTrade, RULES

### Community 67 - "Community 67"
Cohesion: 0.22
Nodes (9): limits, all_in_risk_policy, broker_kill_switch_on_breach, cooldown_seconds, enforce_daily_loss, max_open_positions, max_positions_per_side, max_positions_per_underlying (+1 more)

### Community 68 - "Community 68"
Cohesion: 0.22
Nodes (9): strategy, active_strategies, bar_minutes, ema_fast, ema_slow, max_bars_since_flip, min_distance_atr, supertrend_multiplier (+1 more)

### Community 69 - "Community 69"
Cohesion: 0.22
Nodes (6): @nemesis-oss/ollama-sdk@^1.13.0, @nemesis-oss/ollama-sdk, lastRequest, nextReply, SNAPSHOT, body()

### Community 70 - "Community 70"
Cohesion: 0.22
Nodes (5): Call, client(), NOW, ORDER, SILENT

### Community 71 - "Community 71"
Cohesion: 0.25
Nodes (8): scout, description, mode, orb_requires_close_outside, trend_requires_ema_filter, session, current_posture, postures

### Community 72 - "Community 72"
Cohesion: 0.43
Nodes (8): crossedBelow(), MovingAverage, movingAverage(), alma(), assertPeriod(), hma(), sma(), wma()

### Community 73 - "Community 73"
Cohesion: 0.29
Nodes (7): exits, breakeven_at_rr, max_hold_minutes, runner_mode, stop_loss_pct, target_rr, trailing_jump_pct

### Community 74 - "Community 74"
Cohesion: 0.29
Nodes (6): ink@^5.2.1, react@^18.3.1, ink, react, instance, { runtime, stop }

### Community 75 - "Community 75"
Cohesion: 0.29
Nodes (6): ./tsconfig.json, compilerOptions, noEmit, rootDir, extends, include

### Community 76 - "Community 76"
Cohesion: 0.29
Nodes (5): extends, include, extends, include, ../tsconfig.typecheck.json

### Community 78 - "Community 78"
Cohesion: 0.33
Nodes (6): confirmation_bars, description, mode, orb_requires_close_outside, trend_requires_ema_filter, confirmed

### Community 80 - "Community 80"
Cohesion: 0.47
Nodes (5): rollingWeeklyExpiry(), nominalWeeklyExpiry(), shiftDays(), weekdayOf(), WEEKLY_EXPIRY_WEEKDAY

### Community 81 - "Community 81"
Cohesion: 0.40
Nodes (5): description, mode, orb_requires_close_outside, trend_requires_ema_filter, aligned

### Community 82 - "Community 82"
Cohesion: 0.40
Nodes (5): capital, inr, max_daily_loss_pct, max_lots_per_order, max_risk_per_trade_pct

### Community 83 - "Community 83"
Cohesion: 0.40
Nodes (5): timing, entry_end, entry_start, expiry_day_cutoff, flatten_by

### Community 84 - "Community 84"
Cohesion: 0.67
Nodes (3): GRAPHIFY_BACKEND, has_flag(), graphify.sh script

### Community 85 - "Community 85"
Cohesion: 0.67
Nodes (3): alert(), PATH, session.sh script

### Community 86 - "Community 86"
Cohesion: 0.67
Nodes (3): contract, max_days_to_expiry, min_days_to_expiry

## Knowledge Gaps
- **8 isolated node(s):** `RFC-4648`, `RFC-6238`, `ADR-0001`, `ADR-0012`, `./tsconfig.json` (+3 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 557 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Orchestrator` connect `Community 1` to `Community 64`, `Community 2`, `Community 43`, `Community 13`, `Community 20`, `Community 22`, `Community 23`, `Community 29`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **What connects `RFC-4648`, `RFC-6238`, `ADR-0001` to the rest of the system?**
  _8 weakly-connected nodes found - possible missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08002866698518872 - nodes in this community are weakly interconnected._
- **Why does `istParts()` connect `Community 46` to `Community 0`, `Community 1`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 7`, `Community 9`, `Community 10`, `Community 11`, `Community 13`, `Community 17`, `Community 19`, `Community 21`, `Community 23`, `Community 24`, `Community 28`, `Community 29`, `Community 30`, `Community 31`, `Community 33`, `Community 36`, `Community 39`, `Community 40`, `Community 42`, `Community 43`, `Community 47`, `Community 64`?**
  _High betweenness centrality (0.049) - this node is a cross-community bridge._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05194805194805195 - nodes in this community are weakly interconnected._
- **Why does `StrategySession` connect `Community 43` to `Community 1`, `Community 2`, `Community 13`, `Community 17`, `Community 19`, `Community 21`, `Community 24`, `Community 29`?**
  _High betweenness centrality (0.028) - this node is a cross-community bridge._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.06455399061032864 - nodes in this community are weakly interconnected._
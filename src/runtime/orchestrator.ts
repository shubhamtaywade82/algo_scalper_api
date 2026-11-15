import type { AgentConfig } from '../config.js';
import type { ExecutionPort } from '../execution/ports.js';
import type { TradeAdvisor } from '../llm/advisor.js';
import type { Tick, UnderlyingSpec } from '../domain/types.js';
import { instrumentKey } from '../domain/types.js';
import type { EventLog } from '../ops/eventLog.js';
import type { Logger } from '../ops/logger.js';
import { DayBook } from '../risk/dayBook.js';
import { istParts, shiftDateKey } from '../time/ist.js';
import { assertWarmupClock } from './clockGuard.js';
import type { DiscoveredOpenPosition, FeedPort, MarketPort } from './ports.js';
import { CockpitChainWatch } from './cockpitChainWatch.js';
import { UnderlyingAgent } from './underlyingAgent.js';
import type { CockpitSnapshot, FeedStatusView } from './views.js';
import type { TradingGate } from './tradingGate.js';
import { withDeadline } from './deadline.js';
import { StrategySession, type StrategyId } from '../strategy/session.js';

/** The live feed as the orchestrator sees it: routing, lifecycle and freshness. */
export interface OrchestratorFeed extends FeedPort {
  start(): Promise<void>;
  stop(): void;
  onTick(listener: (tick: Tick) => void): () => void;
  status?(): FeedStatusView;
}

export interface OrchestratorServices {
  /** Pre-restored book for the current IST day. A fresh book is created when omitted. */
  readonly dayBook?: DayBook;
  /** Account capital at the start of the day, after earlier P&L and withdrawals. CAPITAL_INR when omitted. */
  readonly openingCapitalInr?: number;
  readonly market: MarketPort;
  readonly feed: OrchestratorFeed;
  readonly execution: ExecutionPort;
  readonly advisor: TradeAdvisor | undefined;
  readonly events: EventLog;
  readonly logger: Logger;
  readonly now?: () => number;
  readonly clockIntervalMs?: number;
  readonly shutdownTimeoutMs?: number;
  /** Conditions beyond the book that stop orders: the leader lock and unconfirmed events. Open when omitted. */
  readonly gate?: TradingGate;
  /**
   * Runs once, after the final event flush. Ends the run record, releases the leader lock and closes the
   * database and Redis connections. It must not throw, and it must be safe to call twice.
   */
  /** `aborted` is an operator immediate quit; paper mode releases the lease for instant restart. */
  readonly closeSession?: (reason: 'stopped' | 'aborted') => Promise<void>;
}

export type StopKind = 'graceful' | 'immediate';

const DEFAULT_CLOCK_INTERVAL_MS = 1_000;
const BROKER_KILL_RETRY_MS = 30_000;
const DEFAULT_SHUTDOWN_TIMEOUT_MS = 60_000;
const IMMEDIATE_DRAIN_MS = 2_000;

/**
 * Wires the feed, execution venue, market data and one agent per underlying
 * around a single shared DayBook.
 *
 * Breach ordering: a daily-loss breach first blocks new entries in the book,
 * then the agents flatten through their normal exit path, and only once every
 * agent is flat is the broker kill switch engaged. Engaging it first could block
 * the very exit orders that are meant to close the position.
 */
export class Orchestrator {
  private readonly book: DayBook;
  private readonly agents = new Map<string, UnderlyingAgent>();
  private readonly spotIndex = new Map<string, string>();
  private readonly optionIndex = new Map<string, string>();
  private readonly now: () => number;
  private readonly dailyLossLimitInr: number;
  // ponytail: in memory, so a restart restarts the peak from realised P&L; persist it if giveback rules need it.
  private dayPeak = { dayKey: '', pnlInr: 0 };
  private timer: ReturnType<typeof setInterval> | undefined;
  private unsubscribeTicks: (() => void) | undefined;
  private unsubscribeEvents: (() => void) | undefined;
  /** Why the broker kill switch is wanted. Kept for the day: a late fill can reopen a position after an attempt. */
  private brokerKillReason: string | undefined;
  private brokerKillSent = false;
  /** A failed activation is retried no sooner than this, so a broker that keeps refusing is not hammered. */
  private brokerKillRetryAt = 0;
  private brokerKillFailing = false;
  private started = false;
  private stopRequested = false;
  private starting: Promise<void> | undefined;
  private stopPromise: Promise<void> | undefined;
  private phase: CockpitSnapshot['phase'] = 'IDLE';
  private phaseDetail: string | undefined;
  private readonly viewListeners = new Set<() => void>();
  private readonly chainWatch: CockpitChainWatch;
  private readonly strategySession: StrategySession;

  constructor(
    private readonly config: AgentConfig,
    private readonly specs: readonly UnderlyingSpec[],
    private readonly services: OrchestratorServices,
  ) {
    this.now = services.now ?? Date.now;
    this.strategySession = new StrategySession(config.session.initialPosture, config.strategy.enabledStrategies);
    this.book = services.dayBook ?? new DayBook(this.now(), config.exits.cooldownSeconds * 1000, config.capital.enforceDailyLoss);
    this.dailyLossLimitInr = ((services.openingCapitalInr ?? config.capital.inr) * config.capital.maxDailyLossPct) / 100;
    for (const spec of specs) {
      this.agents.set(spec.symbol, this.createAgent(spec));
      this.spotIndex.set(instrumentKey(spec.spot), spec.symbol);
    }
    this.chainWatch = new CockpitChainWatch(
      config,
      specs,
      services.market,
      (symbol, nowMs) => this.agents.get(symbol)?.view(nowMs),
      this.now,
      () => this.notifyView(),
    );
  }

  /** Drives REST chain polling for the cockpit selection only. */
  setCockpitFocus(symbol: string | undefined): void {
    this.chainWatch.setFocus(symbol);
  }

  nudgeCockpitChainScroll(delta: number): boolean {
    return this.chainWatch.nudgeStrikeScroll(delta);
  }

  get dayBook(): DayBook {
    return this.book;
  }

  agent(symbol: string): UnderlyingAgent | undefined {
    return this.agents.get(symbol);
  }

  /** Cockpit redraw hook. Fired on each spot or option tick routed to an agent (not on a timer). */
  onViewUpdate(listener: () => void): () => void {
    this.viewListeners.add(listener);
    return () => {
      this.viewListeners.delete(listener);
    };
  }

  /** Starts the agent. A failed start is recorded in the snapshot so the cockpit can show why. */
  async start(): Promise<void> {
    this.phase = 'STARTING';
    this.starting = this.startInternal();
    try {
      await this.starting;
      if (!this.stopRequested) {
        this.phase = 'RUNNING';
      }
    } catch (error) {
      if (this.stopRequested) {
        // stop() was called mid-start and owns the teardown and the final phase.
        return;
      }
      this.phase = 'FAILED';
      this.phaseDetail = error instanceof Error ? error.message : String(error);
      this.services.logger.error('start failed', { reason: this.phaseDetail });
      throw error;
    }
  }

  private async startInternal(): Promise<void> {
    if (this.started) {
      throw new Error('orchestrator already started');
    }
    this.started = true;

    const openLegs = await this.services.market.brokerOpenOptionCount();
    let adoptable: readonly DiscoveredOpenPosition[] = [];
    if (openLegs > 0) {
      adoptable = (await this.services.market.brokerOpenPositions?.()) ?? [];
      if (adoptable.length !== openLegs || adoptable.length === 0) {
        throw new Error(
          `broker reports ${openLegs} open option position(s) before start; close or adopt them before starting the agent`,
        );
      }
    }
    // An order accepted just before a crash has no position yet, so only the order book can show it.
    const liveOrders = await this.services.market.brokerLiveOrderCount();
    if (liveOrders > 0) {
      throw new Error(
        `broker reports ${liveOrders} order(s) that are not in a terminal status; wait for them to settle or cancel them before starting`,
      );
    }

    const today = istParts(this.now()).date;
    const from = shiftDateKey(today, -(this.config.strategy.warmupDays * 2 + 2));
    const barMs = this.config.strategy.barMinutes * 60_000;
    for (const spec of this.specs) {
      this.assertNotStopping();
      const history = await this.services.market.intradayCandles(spec.spot, this.config.strategy.barMinutes, from, today);
      assertWarmupClock(history[history.length - 1], this.now(), this.config.strategy.barMinutes);
      // The newest warmup bar may still be forming on the exchange; only fully closed bars are seeded.
      const complete = history.filter((bar) => bar.time + barMs <= this.now());
      this.agents.get(spec.symbol)?.seedBars(complete);
      this.services.logger.info('warmup loaded', { underlying: spec.symbol, bars: complete.length });
    }

    // Each step that arms I/O or a timer is preceded by a stop check, so a stop during warmup
    // leaves nothing running. The feed check comes after its await, for the same reason.
    this.assertNotStopping();
    this.unsubscribeTicks = this.services.feed.onTick((tick) => this.route(tick));
    this.unsubscribeEvents = this.services.execution.onEvent((event) => {
      this.agents.get(event.underlying)?.onExecutionEvent(event);
      this.notifyView();
    });
    if (this.config.mode === 'live' && this.config.ops.brokerPnlExit) {
      await this.services.execution.armBrokerPnlExit?.(this.dailyLossLimitInr);
    }
    this.services.execution.start?.();
    await this.services.feed.start();
    if (this.stopRequested) {
      // stop() may already have torn the feed down while this connect was in flight. Tear it down again.
      this.services.feed.stop();
      throw new Error('stop requested while the agent was starting');
    }
    this.services.feed.subscribe(this.specs.map((spec) => spec.spot));
    if (adoptable.length > 0) {
      await this.adoptPositions(adoptable);
    }

    this.timer = setInterval(() => this.onClock(), this.services.clockIntervalMs ?? DEFAULT_CLOCK_INTERVAL_MS);
    this.timer.unref?.();
    for (const agent of this.agents.values()) {
      agent.evaluateWarmupSignal();
    }
    this.services.logger.info('agent running', {
      mode: this.config.mode,
      underlyings: this.specs.map((spec) => spec.symbol),
    });
  }

  private async adoptPositions(positions: readonly DiscoveredOpenPosition[]): Promise<void> {
    for (const pos of positions) {
      const agent = this.agents.get(pos.underlying);
      const spec = this.specs.find((s) => s.symbol === pos.underlying);
      if (agent === undefined || spec === undefined) {
        throw new Error(`cannot adopt position for unknown underlying: ${pos.underlying}`);
      }
      const contracts = await this.services.market.optionContracts(pos.underlying, spec.optionSegment);
      const contract = contracts.find((c) => c.securityId === pos.securityId);
      if (contract === undefined) {
        throw new Error(`cannot adopt position: contract ${pos.securityId} not found in scrip master for ${pos.underlying}`);
      }
      agent.adoptPosition({
        positionId: pos.positionId,
        underlying: pos.underlying,
        contract,
        quantity: pos.quantity,
        averagePrice: pos.averagePrice,
        stopLossPrice: pos.stopLossPrice ?? pos.averagePrice * 0.8,
        targetPrice: pos.targetPrice ?? pos.averagePrice * 1.4,
        openedAt: pos.openedAt ?? this.now(),
      });
      this.services.logger.info('reconciled and adopted open position', {
        underlying: pos.underlying,
        contract: contract.symbol,
        quantity: pos.quantity,
        averagePrice: pos.averagePrice,
      });
    }
  }

  /** True after a stop has finished; used so the entrypoint does not stop twice. */
  hasStopped(): boolean {
    return this.phase === 'STOPPED';
  }

  /**
   * Graceful stop waits for flat positions. Immediate stop tears down I/O at once and, in paper mode,
   * releases the trading lease so the next dev:paper can start without waiting on TTL + order timeout.
   */
  async stop(kind: StopKind = 'graceful'): Promise<void> {
    if (this.stopPromise !== undefined) {
      return this.stopPromise;
    }
    this.stopPromise = this.stopInternal(kind);
    return this.stopPromise;
  }

  private async stopInternal(kind: StopKind): Promise<void> {
    this.stopRequested = true;
    this.phase = 'STOPPING';
    await this.settleStart();
    if (this.timer !== undefined) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    for (const agent of this.agents.values()) {
      agent.requestShutdown();
    }
    let flat = true;
    if (kind === 'graceful') {
      flat = await this.waitUntil(
        () => [...this.agents.values()].every((agent) => agent.isFlat()),
        this.services.shutdownTimeoutMs ?? DEFAULT_SHUTDOWN_TIMEOUT_MS,
        () => {
          for (const agent of this.agents.values()) {
            agent.retryExit();
          }
        },
      );
      if (!flat) {
        this.services.logger.error('shutdown timed out with open positions; live brackets remain at the broker', {});
      }
    } else {
      this.services.logger.warn('immediate shutdown; open positions are not flattened through the agent', {});
    }
    this.unsubscribeTicks?.();
    this.unsubscribeEvents?.();
    const drainMs = kind === 'immediate' ? IMMEDIATE_DRAIN_MS : (this.services.shutdownTimeoutMs ?? DEFAULT_SHUTDOWN_TIMEOUT_MS);
    const drained = await withDeadline(Promise.all([...this.agents.values()].map((agent) => agent.drain())), drainMs, 'drain timed out').then(
      () => true,
      () => false,
    );
    if (!drained) {
      this.services.logger.error('agent queues did not drain in time; work still queued may not be recorded', {});
    }
    this.services.feed.stop();
    await this.services.execution.close();
    await this.services.events.flush();
    const sessionReason = kind === 'immediate' ? 'aborted' : 'stopped';
    await this.services.closeSession?.(sessionReason);
    this.phase = 'STOPPED';
    this.services.logger.info('agent stopped', { kind, flat });
  }

  private allocatedCapitalInr(): number {
    let total = 0;
    for (const agent of this.agents.values()) {
      for (const pos of agent.openPositions) {
        total += pos.averagePrice * pos.quantity;
      }
    }
    return total;
  }

  private computeBalances(realizedPnl: number, dayPnl: number) {
    const initial = this.config.capital.inr;
    const opening = this.services.openingCapitalInr ?? initial;
    const current = Number((opening + realizedPnl).toFixed(2));
    const allocated = Number(this.allocatedCapitalInr().toFixed(2));
    return {
      initialCapitalInr: initial,
      currentBalanceInr: current,
      allocatedBalanceInr: allocated,
      availableBalanceInr: Math.max(0, Number((current - allocated).toFixed(2))),
      realTimeBalanceInr: Number((opening + dayPnl).toFixed(2)),
    };
  }

  /** Read-only state for the operator cockpit. Building it never changes trading state. */
  snapshot(nowMs: number = this.now()): CockpitSnapshot {
    const day = this.book.snapshot();
    const balances = this.computeBalances(day.realizedPnlInr, day.dayPnlInr);
    if (this.dayPeak.dayKey !== day.dayKey) {
      this.dayPeak = { dayKey: day.dayKey, pnlInr: Math.max(0, day.realizedPnlInr) };
    }
    this.dayPeak.pnlInr = Math.max(this.dayPeak.pnlInr, day.dayPnlInr);
    return {
      at: nowMs,
      mode: this.config.mode,
      phase: this.phase,
      phaseDetail: this.phaseDetail,
      capitalInr: balances.initialCapitalInr,
      ...balances,
      riskBudgetInr: (balances.currentBalanceInr * this.config.capital.maxRiskPerTradePct) / 100,
      dailyLossLimitInr: this.dailyLossLimitInr,
      dayPeakPnlInr: this.dayPeak.pnlInr,
      maxTradesPerDay: this.config.capital.maxTradesPerDay,
      maxOpenPositions: this.config.capital.maxOpenPositions,
      maxHoldMinutes: this.config.exits.maxHoldMinutes,
      staleMs: this.config.feed.staleMs,
      contractMaxSpreadPct: this.config.contract.maxSpreadPct,
      contractMinOpenInterest: this.config.contract.minOpenInterest,
      entryStartMinute: this.config.session.entryStartMinute,
      entryEndMinute: this.config.session.entryEndMinute,
      day,
      underlyings: this.specs.flatMap((spec) => {
        const agent = this.agents.get(spec.symbol);
        return agent === undefined ? [] : [agent.view(nowMs)];
      }),
      chainWatch: this.chainWatch.view(nowMs),
      strategy: this.strategySession.view(),
      feed: this.services.feed.status?.(),
    };
  }

  /** Operator request to close one underlying's position. Returns a message for the operator. */
  requestManualExit(symbol: string): string {
    const agent = this.agents.get(symbol);
    if (agent === undefined) {
      return `${symbol}: not traded by this agent`;
    }
    const outcome = agent.requestManualExit();
    const message = {
      ACCEPTED: `${symbol}: close requested; the normal exit checks apply`,
      NO_OPEN_POSITION: `${symbol}: no open position to close`,
      NOT_MANAGEABLE: `${symbol}: position is not in a state that accepts a close right now`,
    }[outcome];
    this.services.logger.warn('operator close request', { underlying: symbol, outcome });
    return message;
  }

  /**
   * Operator toggle for the entry block. Blocking is always allowed. Clearing is refused while
   * any underlying is halted or the day has breached its loss limit, because those need a
   * restart and a review, not a keypress.
   */
  toggleEntryBlock(): string {
    const day = this.book.snapshot();
    if (day.killSwitchReason === undefined) {
      const reason = `operator entry block (${new Date(this.now()).toISOString()})`;
      this.book.activateKillSwitch(reason);
      // Durable, so a restart keeps the block. It is not in the broker kill switch, which does not apply to an operator block.
      this.durableEvent('operator_entry_block', { reason });
      this.services.logger.warn('operator blocked new entries');
      return 'new entries blocked; press k again to clear';
    }
    const halted = [...this.agents.values()].find((agent) => agent.haltedBecause !== undefined);
    if (halted !== undefined) {
      return `cannot clear: ${halted.symbol} is halted (${halted.haltedBecause}); restart after review`;
    }
    if (day.dailyLossBrakeEnabled && day.effectiveDayPnlInr <= -this.dailyLossLimitInr) {
      return 'cannot clear: the daily loss limit is breached for today (press r to reset drawdown)';
    }
    this.book.clearKillSwitch();
    this.durableEvent('operator_entry_clear', {});
    this.services.logger.warn('operator cleared the entry block');
    return 'entry block cleared; new entries may resume';
  }

  /** Resets session drawdown baseline to current P&L, providing fresh daily loss budget. */
  resetDailyDrawdown(): string {
    const baseline = this.book.resetDrawdownBaseline();
    this.durableEvent('daily_loss_reset', { baselineInr: baseline });
    this.services.logger.info('daily drawdown baseline reset', { baselineInr: baseline });
    this.notifyView();
    return `drawdown reset: fresh ₹${Math.round(this.dailyLossLimitInr).toLocaleString('en-IN')} loss budget active`;
  }

  /** Toggles daily loss brake. Refused in live mode for account safety. */
  toggleDailyLossBrake(): string {
    if (this.config.mode === 'live') {
      return 'cannot toggle: daily loss brake is mandatory in live mode';
    }
    const next = !this.book.isDailyLossBrakeEnabled();
    this.book.setDailyLossBrake(next);
    if (!next) {
      this.book.clearKillSwitch();
    }
    this.durableEvent('daily_loss_brake_toggled', { enabled: next });
    this.services.logger.warn('daily loss brake toggled', { enabled: next });
    this.notifyView();
    return `daily loss brake ${next ? 'ENABLED' : 'DISABLED'}`;
  }

  /** Cycles posture (scout -> aligned -> confirmed) across all underlyings without restart. */
  cyclePosture(): string {
    const result = this.strategySession.cyclePosture();
    // Posture changes which signals fire, so it is journalled like any other operator action on trading.
    this.services.events.record('strategy_posture', { posture: this.strategySession.view().posture });
    this.services.logger.info('strategy posture cycled', { posture: this.strategySession.view().posture });
    this.notifyView();
    return result;
  }

  /** Toggles an individual strategy on or off live during the session. */
  toggleStrategy(id: StrategyId): string {
    const result = this.strategySession.toggle(id);
    const enabled = this.strategySession.view().strategies.find((row) => row.id === id)?.on;
    this.services.events.record('strategy_toggled', { id, enabled });
    this.services.logger.info('strategy toggled', { id, result });
    this.notifyView();
    return result;
  }

  /** Triggers an immediate test trade on the live market for fast end-to-end verification without waiting for candle closes. */
  triggerTestTrade(symbol: string, direction?: 'BULLISH' | 'BEARISH'): string {
    if (this.config.mode === 'live') {
      return `${symbol}: test trades are disabled in live mode; switch to paper or sandbox`;
    }
    const agent = this.agents.get(symbol);
    if (agent === undefined) {
      return `${symbol}: not traded by this agent`;
    }
    const result = agent.triggerTestSignal(direction);
    this.services.logger.info('operator test trade triggered', { symbol, direction: direction ?? 'TREND', result });
    this.notifyView();
    return result;
  }

  private createAgent(spec: UnderlyingSpec): UnderlyingAgent {
    const feed: FeedPort = {
      ageMs: (ref) => this.services.feed.ageMs(ref),
      terminalDisconnectCode: () => this.services.feed.terminalDisconnectCode?.(),
      subscribe: (refs) => {
        for (const ref of refs) {
          this.optionIndex.set(instrumentKey(ref), spec.symbol);
        }
        this.services.feed.subscribe(refs);
      },
      unsubscribe: (refs) => {
        for (const ref of refs) {
          this.optionIndex.delete(instrumentKey(ref));
        }
        this.services.feed.unsubscribe(refs);
      },
    };
    return new UnderlyingAgent({
      spec,
      config: this.config,
      market: this.services.market,
      execution: this.services.execution,
      feed,
      advisor: this.services.advisor,
      book: this.book,
      events: this.services.events,
      logger: this.services.logger,
      onHalt: (underlying, reason) => this.onHalt(underlying, reason),
      now: this.now,
      strategySession: this.strategySession,
      ...(this.services.openingCapitalInr === undefined ? {} : { openingCapitalInr: this.services.openingCapitalInr }),
      ...(this.services.gate === undefined ? {} : { gate: this.services.gate }),
    });
  }

  private route(tick: Tick): void {
    const key = instrumentKey(tick);
    const spotSymbol = this.spotIndex.get(key);
    if (spotSymbol !== undefined) {
      this.agents.get(spotSymbol)?.onSpotTick(tick);
      this.notifyView();
      return;
    }
    const optionSymbol = this.optionIndex.get(key);
    if (optionSymbol !== undefined) {
      this.services.execution.onOptionTick(tick);
      this.agents.get(optionSymbol)?.onOptionTick(tick);
      this.notifyView();
    }
  }

  private notifyView(): void {
    for (const listener of this.viewListeners) {
      listener();
    }
  }

  private onClock(): void {
    const now = this.now();
    this.book.observe(now);
    for (const agent of this.agents.values()) {
      agent.onClock(now);
    }
    this.chainWatch.onClock(this.phase);
    this.enforceDailyLoss();
    this.maybeEngageBrokerKillSwitch();
  }

  private enforceDailyLoss(): void {
    const snapshot = this.book.snapshot();
    if (!snapshot.dailyLossBrakeEnabled) {
      return;
    }
    // Keyed on the breach latch, not the kill switch. An operator block may already hold the switch,
    // and that must not stop the breach being journaled or the broker switch being armed.
    if (snapshot.effectiveDayPnlInr > -this.dailyLossLimitInr || snapshot.dailyLossBreach !== undefined) {
      return;
    }
    const reason = `daily loss ${snapshot.effectiveDayPnlInr.toFixed(2)} breached -${this.dailyLossLimitInr.toFixed(2)}`;
    this.book.recordDailyLossBreach(reason);
    this.services.logger.error('daily loss limit breached; flattening', { reason });
    this.durableEvent('daily_loss_breach', { dayPnlInr: snapshot.effectiveDayPnlInr, limitInr: this.dailyLossLimitInr });
    this.brokerKillReason ??= reason;
  }

  /**
   * A halt means an order's fate is unknown or the broker disagrees with us. Entries stop at once in the book.
   * The broker switch waits like a breach does: Dhan refuses to activate it while any position is open, and
   * halted positions are still being exited.
   */
  private onHalt(underlying: string, reason: string): void {
    const fullReason = `${underlying}: ${reason}`;
    this.book.activateKillSwitch(fullReason);
    this.durableEvent('book_kill_switch', { reason: fullReason });
    this.brokerKillReason ??= fullReason;
    this.maybeEngageBrokerKillSwitch();
  }

  /**
   * Engages the broker kill switch whenever the book goes from holding a position to holding none, so it cannot
   * block the exits themselves. It can take more than one attempt: Dhan refuses it while an order is pending,
   * and a halted entry may fill late, so the switch is tried again once that late position is closed.
   * A halted agent's unresolved entry does not hold it back: that order's fate may never be known.
   */
  private maybeEngageBrokerKillSwitch(): void {
    if (this.brokerKillReason === undefined) {
      return;
    }
    const settled = (agent: UnderlyingAgent): boolean =>
      agent.openPositions.length === 0 && (agent.haltedBecause !== undefined || !agent.hasPendingEntry());
    if (![...this.agents.values()].every(settled)) {
      this.brokerKillSent = false;
      return;
    }
    if (this.brokerKillSent || this.now() < this.brokerKillRetryAt) {
      return;
    }
    this.brokerKillSent = true;
    this.engageBrokerKillSwitch(this.brokerKillReason);
  }

  private engageBrokerKillSwitch(reason: string): void {
    const engage = this.services.execution.engageBrokerKillSwitch;
    if (!this.config.ops.brokerKillSwitchOnBreach || engage === undefined) {
      return;
    }
    engage.call(this.services.execution, reason).then(
      () => {
        this.brokerKillFailing = false;
      },
      (error: unknown) => {
        this.services.logger.error('broker kill switch not confirmed; will retry', { reason, error: String(error) });
        this.brokerKillSent = false;
        this.brokerKillRetryAt = this.now() + BROKER_KILL_RETRY_MS;
        if (!this.brokerKillFailing) {
          this.brokerKillFailing = true;
          this.durableEvent('broker_kill_switch_failed', { reason, error: String(error) });
        }
      },
    );
  }

  /**
   * A state change that restart cannot re-derive. It is written durably in the background: the in-memory
   * decision applies at once, and until the write is confirmed the event counts as unconfirmed, which holds entries.
   */
  private durableEvent(type: string, payload: Readonly<Record<string, unknown>>): void {
    this.services.events.durable(type, payload).catch((error: unknown) => {
      this.services.logger.error('event is not durable yet; entries wait until it is recorded', {
        type,
        error: error instanceof Error ? error.message : String(error),
      });
    });
  }

  private assertNotStopping(): void {
    if (this.stopRequested) {
      throw new Error('stop requested while the agent was starting');
    }
  }

  /**
   * Waits for an in-flight start so teardown never runs under it. The wait is bounded by the shutdown
   * timeout: a hung connect must not make the operator's stop hang with it.
   */
  private async settleStart(): Promise<void> {
    if (this.starting === undefined) {
      return;
    }
    // Not unref'd: shutdown must still complete if nothing else is holding the process open.
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<'timeout'>((resolve) => {
      timer = setTimeout(() => resolve('timeout'), this.services.shutdownTimeoutMs ?? DEFAULT_SHUTDOWN_TIMEOUT_MS);
    });
    const outcome = await Promise.race([this.starting.then(() => 'settled' as const, () => 'settled' as const), timeout]);
    clearTimeout(timer);
    if (outcome === 'timeout') {
      this.services.logger.warn('start still in progress at stop; continuing shutdown', {});
    }
  }

  private async waitUntil(predicate: () => boolean, timeoutMs: number, onPoll: () => void = () => undefined): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (!predicate()) {
      if (Date.now() >= deadline) {
        return false;
      }
      onPoll();
      await new Promise<void>((resolve) => setTimeout(resolve, 250));
    }
    return true;
  }
}

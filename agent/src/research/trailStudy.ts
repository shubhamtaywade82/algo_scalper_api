import type { Candle, OptionSegment } from '../domain/types.js';
import { OPEN_TRAIL, onBarClosed, onTouch, type TrailPosition, type TrailSpec, type TrailState } from '../exits/trail.js';
import { bracketLevels, calculateTrailingStop, roundDownToTick, roundTripChargesInr } from '../options/pricing.js';
import { marketStructure, structureTurnedAgainst } from '../strategy/marketContext.js';
import { istParts } from '../time/ist.js';
import { legBars, type ResearchSession } from './dataset.js';
import type { FineBars } from './studyEntries.js';
import type { CostModel, ReplayConfig, ReplayExitReason, ReplayTrade } from './replay.js';

/**
 * Fixed-entry study (docs/TRAILING_STOPS.md §5.2). Entries come from one baseline replay and are frozen; each exit
 * policy is then replayed over the same entry, so a difference between policies is an exit effect only.
 * The bar rules are `replaySession.step`'s, and a test holds the baseline policy to the replay's own exits.
 */

export type ExitPolicy = { readonly kind: 'NONE' } | { readonly kind: 'B1' } | { readonly kind: 'TRAIL'; readonly spec: TrailSpec };

export interface StudyOptions {
  /** KEEP: the bracket target stays, as live. NONE: no target; only the trail and the forced exits close. */
  readonly target: 'KEEP' | 'NONE';
  readonly structureExit: boolean;
}

/** A frozen entry: the baseline trade plus the bars it needs. */
export interface StudyEntry {
  readonly trade: ReplayTrade;
  readonly session: ResearchSession;
  /** Spot bars before the session, as the replay's warmup. */
  readonly warmup: readonly Candle[];
  readonly optionSegment: OptionSegment;
  readonly underlying: string;
}

export type StudyExitReason = ReplayExitReason | 'TRAILING_STOP';

export interface StudyTrade {
  readonly date: string;
  readonly entryTime: number;
  readonly exitTime: number;
  readonly exitPrice: number;
  readonly exitReason: StudyExitReason;
  readonly netPnlInr: number;
  readonly riskInr: number;
  readonly r: number;
  /** Best executable exit inside the shared window, in rupees, never below zero (§5.1). Same for every policy. */
  readonly opportunityInr: number;
  readonly trailFallback: string | undefined;
}

/** Spot bars the trail sees. ATR(14) and SuperTrend(10) have converged long before this; it bounds the work. */
const TRAIL_SPOT_BARS = 300;

interface Open {
  stop: number;
  highWaterMark: number;
  lastMark: number;
  trail: TrailState;
  flagged: StudyExitReason | undefined;
  /** The flagged exit came from a touch on the underlying: it fills like a stop, not at the bid. */
  flaggedIsStop: boolean;
}

function pricing(entry: StudyEntry, costs: CostModel) {
  const tick = entry.session.tickSize;
  return {
    bid: (price: number): number => Math.max(tick, roundDownToTick(price * (1 - costs.halfSpreadPct / 100), tick)),
    stopFill: (price: number): number => Math.max(tick, roundDownToTick(price * (1 - (costs.halfSpreadPct + costs.stopSlippagePct) / 100), tick)),
  };
}

function trailPosition(entry: StudyEntry, config: ReplayConfig, costs: CostModel): TrailPosition {
  const { trade } = entry;
  const charges = roundTripChargesInr({ quantity: trade.quantity, buyPrice: trade.entryPrice, sellPrice: trade.entryPrice, exchangeSegment: entry.optionSegment });
  return {
    entryPrice: trade.entryPrice,
    initialStop: trade.initialStopPrice,
    side: trade.optionType === 'CE' ? 1 : -1,
    entryTime: trade.entryTime,
    barMs: config.barMinutes * 60_000,
    halfSpreadPct: costs.halfSpreadPct,
    chargesPerUnit: charges / trade.quantity,
  };
}

/** The shared window: from entry until the first forced exit common to every policy (EOD flatten, time stop). */
export function opportunityInr(entry: StudyEntry, config: ReplayConfig, costs: CostModel): number {
  const { trade } = entry;
  const { bid } = pricing(entry, costs);
  let best = trade.entryPrice;
  for (const bar of legBars(entry.session, trade.optionType, trade.strike) ?? []) {
    const inWindow =
      bar.time >= trade.entryTime &&
      istParts(bar.time).minuteOfDay < config.exits.flattenByMinute &&
      bar.time - trade.entryTime < config.exits.maxHoldMinutes * 60_000;
    best = inWindow ? Math.max(best, bid(bar.high)) : best;
  }
  return Number(((best - trade.entryPrice) * trade.quantity).toFixed(2));
}

interface Exit {
  readonly time: number;
  readonly price: number;
  readonly reason: StudyExitReason;
}

interface PathContext {
  readonly entry: StudyEntry;
  readonly policy: ExitPolicy;
  readonly config: ReplayConfig;
  readonly target: number;
  readonly position: TrailPosition;
  readonly bid: (price: number) => number;
  readonly stopFill: (price: number) => number;
}

function stopReason(ctx: PathContext, open: Open): StudyExitReason {
  return open.stop > ctx.entry.trade.initialStopPrice && ctx.policy.kind === 'TRAIL' ? 'TRAILING_STOP' : 'STOP_LOSS';
}

/** The exits decided at a bar boundary: a flagged exit, EOD flatten or the time stop, at the bar's open. */
function forcedAtOpen(ctx: PathContext, open: Open, bar: Candle): Exit | undefined {
  const { config, entry } = ctx;
  const minute = istParts(bar.time).minuteOfDay;
  const reason: StudyExitReason | undefined =
    open.flagged ??
    (minute >= config.exits.flattenByMinute ? 'EOD_FLATTEN' : bar.time - entry.trade.entryTime >= config.exits.maxHoldMinutes * 60_000 ? 'TIME_STOP' : undefined);
  return reason === undefined ? undefined : { time: bar.time, price: open.flaggedIsStop ? ctx.stopFill(bar.open) : ctx.bid(bar.open), reason };
}

/**
 * The exit checks for one bar, walked over its sub-bars (the bar itself without fine data). The open is unusable on
 * the entry bar, where it priced the fill. A touch of the underlying level on a sub-bar exits at the next sub-bar's open.
 */
function barExit(ctx: PathContext, open: Open, subBars: readonly Candle[], spotSubBars: readonly Candle[] | undefined, entryBar: boolean): Exit | undefined {
  let underlyingHit = false;
  for (const [k, sub] of subBars.entries()) {
    if (!(entryBar && k === 0)) {
      if (sub.open <= open.stop) return { time: sub.time, price: ctx.stopFill(sub.open), reason: stopReason(ctx, open) };
      if (ctx.bid(sub.open) >= ctx.target) return { time: sub.time, price: ctx.target, reason: 'TARGET' };
      const forced = k === 0 ? forcedAtOpen(ctx, open, sub) : underlyingHit ? { time: sub.time, price: ctx.stopFill(sub.open), reason: 'TRAILING_STOP' as const } : undefined;
      if (forced !== undefined) return forced;
    }
    if (sub.low <= open.stop) return { time: sub.time, price: ctx.stopFill(open.stop), reason: stopReason(ctx, open) };
    if (ctx.bid(sub.high) >= ctx.target) return { time: sub.time, price: ctx.target, reason: 'TARGET' };
    const spot = spotSubBars?.[k];
    if (spot !== undefined && !underlyingHit) {
      open.trail = onTouch(open.trail, 'UNDERLYING', ctx.position.side === 1 ? spot.low : spot.high, ctx.position.side);
      underlyingHit = open.trail.phase === 'TRIGGERED';
    }
  }
  return undefined;
}

/** Replays one frozen entry under one exit policy, on its 5-minute bars or, with `fine`, on their 1-minute bars. */
export function exitPath(entry: StudyEntry, policy: ExitPolicy, options: StudyOptions, config: ReplayConfig, costs: CostModel, fine?: FineBars): StudyTrade {
  const { trade, session } = entry;
  const premiumAll = legBars(session, trade.optionType, trade.strike) ?? [];
  const premiumByTime = new Map(premiumAll.map((bar) => [bar.time, bar]));
  const ctx: PathContext = { entry, policy, config, target: options.target === 'KEEP' ? trade.targetPrice : Infinity, position: trailPosition(entry, config, costs), ...pricing(entry, costs) };
  const jump = policy.kind === 'B1' ? bracketJump(trade, config, session.tickSize) : undefined;
  const history: Candle[] = [...entry.warmup];
  const open: Open = { stop: trade.initialStopPrice, highWaterMark: trade.entryPrice, lastMark: trade.entryPrice, trail: OPEN_TRAIL, flagged: undefined, flaggedIsStop: false };
  const finish = (exit: Exit): StudyTrade => studyTrade(entry, config, costs, exit.time, exit.price, exit.reason, open.trail.fallback);
  for (const spotBar of session.spot) {
    const time = spotBar.time;
    if (time < trade.entryTime) {
      history.push(spotBar);
      continue;
    }
    const bar = premiumByTime.get(time);
    const subBars = fine === undefined ? (bar === undefined ? undefined : [bar]) : fine.premium.get(time);
    if (bar === undefined || subBars === undefined || subBars.length === 0) {
      return finish({ time, price: ctx.bid(open.lastMark), reason: 'DATA_GAP' });
    }
    const exit = barExit(ctx, open, subBars, fine?.spot.get(time), time === trade.entryTime);
    if (exit !== undefined) {
      return finish(exit);
    }
    open.lastMark = bar.close;
    history.push(spotBar);
    advance(open, policy, jump, { trade, position: ctx.position, history, premiumAll, time, spotBar, tick: session.tickSize, breakevenAtRr: config.exits.breakevenAtRr });
    if (open.flagged === undefined && options.structureExit) {
      open.flagged = structureTurnedAgainst(marketStructure(history), trade.optionType === 'CE' ? 'BULLISH' : 'BEARISH') ? 'STRUCTURE_BREAK' : undefined;
    }
  }
  const last = session.spot.at(-1);
  return finish({ time: last === undefined ? trade.entryTime : last.time + config.barMinutes * 60_000, price: ctx.bid(open.lastMark), reason: 'EOD_FLATTEN' });
}

interface AdvanceInput {
  readonly trade: ReplayTrade;
  readonly position: TrailPosition;
  readonly history: readonly Candle[];
  readonly premiumAll: readonly Candle[];
  readonly time: number;
  readonly spotBar: Candle;
  readonly tick: number;
  readonly breakevenAtRr: number;
}

export interface TrailStep {
  readonly trail: TrailState;
  /** The premium stop after this bar: the old stop, tightened to the trail's premium level. */
  readonly stop: number;
  /** The trail fired: exit at the next bar's open, as a stop-market fill. */
  readonly exitNextOpen: boolean;
}

/**
 * One bar close for a trail, shared by the fixed-entry study and the coupled replay. The underlying touch is checked
 * against the level set before this bar, so the bar cannot move its own stop. Takes effect from the next bar.
 */
export function trailBarClose(spec: TrailSpec, position: TrailPosition, state: TrailState, input: { spot: readonly Candle[]; premium: readonly Candle[]; spotBar: Candle; stop: number; tick: number }): TrailStep {
  let trail = onTouch(state, 'UNDERLYING', position.side === 1 ? input.spotBar.low : input.spotBar.high, position.side);
  if (trail.phase !== 'TRIGGERED') {
    trail = onBarClosed(spec, position, trail, { spot: input.spot.slice(-TRAIL_SPOT_BARS), premium: input.premium });
  }
  const level = trail.levels.PREMIUM;
  const stop = level === undefined ? input.stop : Math.max(input.stop, roundDownToTick(level, input.tick));
  return { trail, stop, exitNextOpen: trail.intent !== undefined };
}

/** Moves the stop after a bar closes. Takes effect from the next bar, never inside the bar that set it. */
function advance(open: Open, policy: ExitPolicy, jump: number | undefined, input: AdvanceInput): void {
  if (policy.kind === 'B1' && jump !== undefined && jump > 0) {
    const bar = input.premiumAll.find((candle) => candle.time === input.time);
    open.highWaterMark = Math.max(open.highWaterMark, bar?.high ?? open.highWaterMark);
    open.stop = calculateTrailingStop({
      entryPrice: input.trade.entryPrice,
      initialStopPrice: input.trade.initialStopPrice,
      currentStopPrice: open.stop,
      highWaterMark: open.highWaterMark,
      trailingJump: jump,
      breakevenAtRr: input.breakevenAtRr,
      tickSize: input.tick,
    });
    return;
  }
  if (policy.kind !== 'TRAIL') {
    return;
  }
  const premium = input.premiumAll.filter((candle) => candle.time <= input.time);
  const step = trailBarClose(policy.spec, input.position, open.trail, { spot: input.history, premium, spotBar: input.spotBar, stop: open.stop, tick: input.tick });
  open.trail = step.trail;
  open.stop = step.stop;
  if (step.exitNextOpen) {
    open.flagged = 'TRAILING_STOP';
    // Every trail exit is a market SELL into an adverse move, so it pays stop slippage like the stop leg does.
    // Filling a close-confirmed exit at the plain bid would hand those methods a cost edge over B1's stops.
    open.flaggedIsStop = true;
  }
}

function bracketJump(trade: ReplayTrade, config: ReplayConfig, tick: number): number | undefined {
  return bracketLevels({
    entryReference: trade.entryLimit,
    stopLossPct: config.exits.stopLossPct,
    targetRr: config.exits.targetRr,
    tickSize: tick,
    trailingJumpPct: config.exits.trailingJumpPct,
  })?.trailingJump;
}

function studyTrade(
  entry: StudyEntry,
  config: ReplayConfig,
  costs: CostModel,
  exitTime: number,
  exitPrice: number,
  exitReason: StudyExitReason,
  trailFallback: string | undefined,
): StudyTrade {
  const { trade } = entry;
  const gross = Number(((exitPrice - trade.entryPrice) * trade.quantity).toFixed(2));
  const charges = roundTripChargesInr({ quantity: trade.quantity, buyPrice: trade.entryPrice, sellPrice: exitPrice, exchangeSegment: entry.optionSegment });
  const netPnlInr = Number((gross - charges).toFixed(2));
  return {
    date: trade.date,
    entryTime: trade.entryTime,
    exitTime,
    exitPrice,
    exitReason,
    netPnlInr,
    riskInr: trade.riskInr,
    r: Number((netPnlInr / trade.riskInr).toFixed(4)),
    opportunityInr: opportunityInr(entry, config, costs),
    trailFallback,
  };
}

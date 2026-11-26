import type { AgentConfig } from '../config.js';
import type { Candle, Direction, OptionSegment, OptionType, Signal } from '../domain/types.js';
import { OPEN_TRAIL, type TrailPosition, type TrailSpec, type TrailState } from '../exits/trail.js';
import { bracketLevels, calculateTrailingStop, roundDownToTick, roundTripChargesInr, roundUpToTick } from '../options/pricing.js';
import { directionToOptionType, nearestAtmStrike, targetEntryStrike } from '../options/selector.js';
import { sizePosition } from '../options/sizing.js';
import { adverseCostsFor, allInAdverseLossInr, stopExitPrice } from '../risk/allInLoss.js';
import { evaluatePreTrade } from '../risk/riskEngine.js';
import { contextVerdict, marketContext, marketStructure, structureTurnedAgainst, type MarketContext } from '../strategy/marketContext.js';
import type { OrbSupertrendParams } from '../strategy/orbSupertrend.js';
import { StrategySession, type StrategyId, type StrategyPosture } from '../strategy/session.js';
import { dayDifference, nominalMonthlyExpiry, nominalWeeklyExpiry } from '../time/calendar.js';
import { istParts, NSE_SESSION_OPEN_MINUTE } from '../time/ist.js';
import { legBars, sessionStrikes, type ResearchDataset, type ResearchSession } from './dataset.js';
import { atmIvAt, atmIvByMinute, ivBucketFor, trailingIvHistory, type IvBucket, type IvHistory, type IvSessionMaps } from './ivContext.js';
import {
  expiryBucket,
  structureAlignment,
  volatilityBucket,
  type ExpiryBucket,
  type StructureAlignment,
  type VolatilityBucket,
} from './tradeFeatures.js';
import { trailBarClose } from './trailStudy.js';

/** The live settings a replay honours. Built from AgentConfig so a replay runs the rules the agent would run. */
export interface ReplayConfig {
  readonly barMinutes: number;
  /** Prior sessions seeded into the bar history before each day, as the live warmup does. */
  readonly warmupSessions: number;
  readonly posture: StrategyPosture;
  readonly enabledStrategies: readonly StrategyId[] | undefined;
  readonly strategy: Omit<OrbSupertrendParams, 'underlying'>;
  readonly contextGate: boolean;
  readonly structureExit: boolean;
  readonly strikeOffsetSteps: number;
  readonly entryLimitBufferPct: number;
  readonly expiryDayEntryCutoffMinute: number;
  /**
   * The live contract limits, in calendar days to expiry. A session whose contract is outside them takes no entry.
   * Undefined applies no limit. A maximum of zero is no upper limit, as in the live selector (`pickExpiry`).
   */
  readonly minDaysToExpiry?: number | undefined;
  readonly maxDaysToExpiry?: number | undefined;
  readonly exits: AgentConfig['exits'];
  readonly capital: Pick<
    AgentConfig['capital'],
    'inr' | 'maxRiskPerTradePct' | 'maxDailyLossPct' | 'maxTradesPerDay' | 'maxLotsPerOrder' | 'allInRiskPolicy'
  >;
  /** Research only (coupled trailing study): this trail replaces the bracket's trailing jump. */
  readonly trail?: TrailSpec | undefined;
  /** Research only: no target leg, so only stops, the trail and forced exits close a position. */
  readonly noTarget?: boolean | undefined;
}

/**
 * Historical bars carry trade prints, not quotes. Every fill is therefore priced off a print plus an assumed
 * spread, and the assumption is reported with every result.
 */
export interface CostModel {
  /** Half the bid/ask spread, % of premium. A buy pays it; a sell gives it up. */
  readonly halfSpreadPct: number;
  /** Slippage on a stop-market fill beyond the half spread, % of premium. */
  readonly stopSlippagePct: number;
}

export type ReplayExitReason = 'STOP_LOSS' | 'TARGET' | 'TIME_STOP' | 'EOD_FLATTEN' | 'DAILY_LOSS' | 'STRUCTURE_BREAK' | 'DATA_GAP' | 'TRAILING_STOP';

export interface ReplayTrade {
  readonly date: string;
  readonly strategy: string;
  readonly direction: Direction;
  readonly optionType: OptionType;
  readonly strike: number;
  /** Open time of the closed spot bar that produced the signal. */
  readonly signalBarTime: number;
  readonly entryTime: number;
  readonly exitTime: number;
  readonly entryLimit: number;
  readonly entryPrice: number;
  readonly initialStopPrice: number;
  readonly finalStopPrice: number;
  readonly targetPrice: number;
  readonly exitPrice: number;
  readonly lots: number;
  readonly quantity: number;
  /** Planned rupee risk at the initial stop, from the limit price. The denominator of R. */
  readonly riskInr: number;
  readonly grossPnlInr: number;
  readonly chargesInr: number;
  readonly netPnlInr: number;
  /** Net P&L over planned risk. */
  readonly r: number;
  readonly exitReason: ReplayExitReason;
  /** One bar touched both the stop and the target; counted as the stop. */
  readonly ambiguousBar: boolean;
  /** The bar opened below the stop, so the fill was worse than the stop price. */
  readonly gapThroughStop: boolean;
  readonly context: TradeContext;
}

/** Conditions at the signal, all known when it fired, so results can be judged per context. */
export interface TradeContext {
  readonly regime: MarketContext['regime'];
  /** The day's trend against the trade's direction. */
  readonly trendAlignment: 'WITH' | 'AGAINST' | 'NEUTRAL';
  readonly timeBucket: 'OPEN' | 'MID' | 'LATE';
  readonly expiryDay: boolean;
  /** ATR tercile of its own history at the signal bar. */
  readonly volatility: VolatilityBucket;
  /** Market-structure trend against the trade's direction. */
  readonly structureAlignment: StructureAlignment;
  /** Sessions to expiry, or UNKNOWN where the session has no expiry on record. */
  readonly expiryBucket: ExpiryBucket;
  /** ATM implied volatility at the signal, against the trailing sessions at the same minute. Research only: it never changes a trade. */
  readonly ivBucket: IvBucket;
  /** Not replayed: there is no historical option chain. Always UNKNOWN, never a neutral stand-in. */
  readonly chainBias: 'UNKNOWN';
}

const MID_SESSION_MINUTE = 10 * 60 + 30;
const LATE_SESSION_MINUTE = 12 * 60 + 30;

/**
 * Context at the signal bar. `history` ends at that bar, so every feature here is known when the trade is taken (OTA-309).
 */
function tradeContext(
  context: MarketContext,
  direction: Direction,
  signalBarTime: number,
  session: ResearchSession,
  history: readonly Candle[],
  ivBucket: IvBucket,
): TradeContext {
  const minute = istParts(signalBarTime).minuteOfDay;
  return {
    regime: context.regime,
    trendAlignment: context.dayTrend === 'NEUTRAL' ? 'NEUTRAL' : context.dayTrend === direction ? 'WITH' : 'AGAINST',
    timeBucket: minute < MID_SESSION_MINUTE ? 'OPEN' : minute < LATE_SESSION_MINUTE ? 'MID' : 'LATE',
    expiryDay: session.expiry === session.date,
    volatility: volatilityBucket(history),
    structureAlignment: structureAlignment(context.structure, direction),
    expiryBucket: expiryBucket(session.date, session.expiry),
    ivBucket,
    chainBias: 'UNKNOWN',
  };
}

export interface ReplayResult {
  readonly trades: readonly ReplayTrade[];
  /** Days replayed, including days with no trade. Needed to resample by day. */
  readonly dates: readonly string[];
  readonly signals: number;
  /** Signals that did not become trades, by stable code. */
  readonly drops: Readonly<Record<string, number>>;
  /** Live rules the replay cannot reproduce from historical bars. */
  readonly divergences: readonly string[];
}

export function replayConfigFrom(config: AgentConfig): { replay: ReplayConfig; divergences: string[] } {
  const divergences: string[] = [];
  if (config.chainAnalysis.enabled) {
    divergences.push('chain OI-resistance gate is not replayed (no historical option chain); trades it would veto are included');
  }
  if (config.context.enabled) {
    divergences.push('context gate is replayed with chain bias NEUTRAL (no historical option chain)');
  }
  divergences.push('MAX_SPREAD_PCT, MIN_OPEN_INTEREST and MIN_VOLUME are not replayed (bars carry no quotes); the spread is the cost model');
  divergences.push('a session outside MIN_DAYS_TO_EXPIRY / MAX_DAYS_TO_EXPIRY takes no entry; where live would pick a later expiry instead, the replay cannot (the dataset holds one expiry code)');
  if (config.capital.maxOpenPositions > 1 || config.capital.maxPositionsPerSide > 1) {
    divergences.push('one position at a time per replay; concurrent CE and PE positions are not modelled');
  }
  const { strategy, session, contract, exits, capital } = config;
  return {
    replay: {
      barMinutes: strategy.barMinutes,
      warmupSessions: strategy.warmupDays,
      posture: session.initialPosture,
      enabledStrategies: strategy.enabledStrategies,
      strategy: {
        orbMinutes: strategy.orbMinutes,
        barMinutes: strategy.barMinutes,
        supertrendPeriod: strategy.supertrendPeriod,
        supertrendMultiplier: strategy.supertrendMultiplier,
        emaFast: strategy.emaFast,
        emaSlow: strategy.emaSlow,
        entryStartMinute: session.entryStartMinute,
        entryEndMinute: session.entryEndMinute,
        sessionOpenMinute: NSE_SESSION_OPEN_MINUTE,
        maxBarsSinceFlip: strategy.maxBarsSinceFlip,
        minDistanceAtr: strategy.minDistanceAtr,
      },
      contextGate: config.context.enabled,
      structureExit: config.context.structureExit,
      strikeOffsetSteps: contract.strikeOffsetSteps,
      entryLimitBufferPct: contract.entryLimitBufferPct,
      expiryDayEntryCutoffMinute: contract.expiryDayEntryCutoffMinute,
      minDaysToExpiry: contract.minDaysToExpiry,
      maxDaysToExpiry: contract.maxDaysToExpiry,
      exits,
      capital: {
        inr: capital.inr,
        maxRiskPerTradePct: capital.maxRiskPerTradePct,
        maxDailyLossPct: capital.maxDailyLossPct,
        maxTradesPerDay: capital.maxTradesPerDay,
        maxLotsPerOrder: capital.maxLotsPerOrder,
        allInRiskPolicy: capital.allInRiskPolicy,
      },
    },
    divergences,
  };
}

/** The widest spread the live gate accepts is MAX_SPREAD_PCT, so half of it is the worst accepted half-spread. */
export function defaultCostModel(config: AgentConfig): CostModel {
  return adverseCostsFor(config);
}

interface PendingEntry {
  readonly strategy: string;
  readonly direction: Direction;
  readonly optionType: OptionType;
  readonly strike: number;
  readonly signalBarTime: number;
  readonly context: TradeContext;
}

interface HeldPosition extends PendingEntry {
  readonly bars: ReadonlyMap<number, Candle>;
  readonly entryTime: number;
  readonly entryLimit: number;
  readonly entryPrice: number;
  readonly initialStopPrice: number;
  stopLossPrice: number;
  readonly targetPrice: number;
  readonly trailingJump: number | undefined;
  highWaterMark: number;
  readonly lots: number;
  readonly quantity: number;
  readonly riskInr: number;
  lastMark: number;
  /** An exit decided at a bar close (structure, daily loss) executes at the next bar's open. */
  flaggedExit: ReplayExitReason | undefined;
  /** A flagged trail exit is a stop-market SELL: it fills with stop slippage, not at the plain bid. */
  flaggedIsStop: boolean;
  trail: TrailState;
  readonly trailPosition: TrailPosition;
  readonly premiumSeries: readonly Candle[];
}

/** Advances the held position's trail at a bar close; true when it fired and the position exits at the next open. */
function applyTrail(spec: TrailSpec, held: HeldPosition, history: readonly Candle[], spotBar: Candle, tick: number): boolean {
  const premium = held.premiumSeries.filter((bar) => bar.time <= spotBar.time);
  const step = trailBarClose(spec, held.trailPosition, held.trail, { spot: history, premium, spotBar, stop: held.stopLossPrice, tick });
  held.trail = step.trail;
  held.stopLossPrice = step.stop;
  return step.exitNextOpen;
}

interface DayState {
  realizedInr: number;
  trades: number;
  cooldownUntil: number;
}

/**
 * Replays the live entry and exit rules over historical sessions, bar by bar, using only what was known at each
 * bar close. Signals come from the same StrategySession the agent runs; brackets, sizing and charges from the
 * same functions. Fills are priced pessimistically wherever a 5-minute bar cannot say what happened inside it.
 */
/**
 * The expiry each session trades against, for a rolling-option dataset, which records no expiry. Only the nearest contract
 * (expiry code 1) has a rule: the weekly calendar for a weekly series and the monthly calendar for a monthly one. Look-ahead
 * free: it depends on the session's own date only. Undefined for a later expiry code, and each session gets undefined where
 * the index has no recorded rule.
 */
export function rollingExpiry(dataset: ResearchDataset): ((date: string) => string | undefined) | undefined {
  const { kind, expiryFlag, expiryCode } = dataset.source;
  if (kind !== 'dhan_rollingoption' || (expiryCode ?? 1) !== 1) {
    return undefined;
  }
  const rule = expiryFlag === 'MONTH' ? nominalMonthlyExpiry : nominalWeeklyExpiry;
  return (date) => rule(dataset.underlying, date);
}

/** True when the contract's calendar days to expiry are inside the configured limits. An unknown expiry is not limited. */
function expiryWithinLimits(session: ResearchSession, config: ReplayConfig): boolean {
  if (session.expiry === undefined) {
    return true;
  }
  const days = dayDifference(session.date, session.expiry);
  const { minDaysToExpiry, maxDaysToExpiry } = config;
  if (minDaysToExpiry !== undefined && days < minDaysToExpiry) {
    return false;
  }
  return maxDaysToExpiry === undefined || maxDaysToExpiry <= 0 || days <= maxDaysToExpiry;
}

/**
 * Sees every bar where the replay looks for an entry: every enabled family's signal, and the one first-match credited.
 * Research only (OTA-307). It never changes which trade is taken.
 */
export interface EntryObserver {
  onEntryBar(candidates: readonly Signal[], credited: Signal | undefined): void;
}

export function replayDataset(
  dataset: ResearchDataset,
  config: ReplayConfig,
  costs: CostModel,
  divergences: readonly string[] = [],
  observer?: EntryObserver,
): ReplayResult {
  if (dataset.barMinutes !== config.barMinutes) {
    throw new Error(`dataset bars are ${dataset.barMinutes}-minute but BAR_MINUTES is ${config.barMinutes}`);
  }
  if (!(costs.halfSpreadPct >= 0) || !(costs.stopSlippagePct >= 0)) {
    throw new RangeError('cost model percentages must be non-negative');
  }
  const strategySession = new StrategySession(config.posture, config.enabledStrategies);
  const params: OrbSupertrendParams = { ...config.strategy, underlying: dataset.underlying };
  const trades: ReplayTrade[] = [];
  const drops: Record<string, number> = {};
  let signals = 0;
  const drop = (code: string): void => {
    drops[code] = (drops[code] ?? 0) + 1;
  };

  const expiryOf = rollingExpiry(dataset);
  let undatedSessions = 0;
  const atmIv: IvSessionMaps[] = dataset.sessions.map((session) => ({ CE: atmIvByMinute(session, 'CE'), PE: atmIvByMinute(session, 'PE') }));
  dataset.sessions.forEach((session, index) => {
    const warmup = dataset.sessions.slice(Math.max(0, index - config.warmupSessions), index).flatMap((day) => day.spot);
    const expiry = session.expiry ?? expiryOf?.(session.date);
    const dated = expiry === undefined ? session : { ...session, expiry };
    undatedSessions += expiry === undefined ? 1 : 0;
    const outcome = replaySession(dated, warmup, dataset.optionSegment, config, costs, strategySession, params, drop, trailingIvHistory(atmIv, index), observer);
    signals += outcome.signals;
    trades.push(...outcome.trades);
  });
  const limited = config.minDaysToExpiry !== undefined || config.maxDaysToExpiry !== undefined;
  const reported =
    limited && undatedSessions > 0
      ? [...divergences, `expiry limits are not applied to ${undatedSessions} session(s) with no expiry on record`]
      : divergences;
  return { trades, dates: dataset.sessions.map((session) => session.date), signals, drops, divergences: reported };
}

function replaySession(
  session: ResearchSession,
  warmup: readonly Candle[],
  optionSegment: OptionSegment,
  config: ReplayConfig,
  costs: CostModel,
  strategySession: StrategySession,
  params: OrbSupertrendParams,
  drop: (code: string) => void,
  ivHistory: IvHistory,
  observer: EntryObserver | undefined,
): { trades: ReplayTrade[]; signals: number } {
  const barMs = config.barMinutes * 60_000;
  const tick = session.tickSize;
  const dailyLossLimitInr = (config.capital.inr * config.capital.maxDailyLossPct) / 100;
  const history: Candle[] = [...warmup];
  const day: DayState = { realizedInr: 0, trades: 0, cooldownUntil: 0 };
  const trades: ReplayTrade[] = [];
  let signals = 0;
  let pending: PendingEntry | undefined;
  let position: HeldPosition | undefined;

  const ask = (price: number): number => roundUpToTick(price * (1 + costs.halfSpreadPct / 100), tick);
  const bid = (price: number): number => Math.max(tick, roundDownToTick(price * (1 - costs.halfSpreadPct / 100), tick));
  const stopReason = (held: HeldPosition): ReplayExitReason =>
    config.trail !== undefined && held.stopLossPrice > held.initialStopPrice ? 'TRAILING_STOP' : 'STOP_LOSS';
  const stopFill = (price: number): number => stopExitPrice(price, costs, tick);

  const close = (held: HeldPosition, exitTime: number, exitPrice: number, exitReason: ReplayExitReason, flags: { ambiguousBar?: boolean; gapThroughStop?: boolean } = {}): void => {
    const grossPnlInr = Number(((exitPrice - held.entryPrice) * held.quantity).toFixed(2));
    const chargesInr = roundTripChargesInr({ quantity: held.quantity, buyPrice: held.entryPrice, sellPrice: exitPrice, exchangeSegment: optionSegment });
    const netPnlInr = Number((grossPnlInr - chargesInr).toFixed(2));
    trades.push({
      date: session.date,
      strategy: held.strategy,
      direction: held.direction,
      optionType: held.optionType,
      strike: held.strike,
      signalBarTime: held.signalBarTime,
      entryTime: held.entryTime,
      exitTime,
      entryLimit: held.entryLimit,
      entryPrice: held.entryPrice,
      initialStopPrice: held.initialStopPrice,
      finalStopPrice: held.stopLossPrice,
      targetPrice: held.targetPrice,
      exitPrice,
      lots: held.lots,
      quantity: held.quantity,
      riskInr: held.riskInr,
      grossPnlInr,
      chargesInr,
      netPnlInr,
      r: Number((netPnlInr / held.riskInr).toFixed(4)),
      exitReason,
      ambiguousBar: flags.ambiguousBar ?? false,
      gapThroughStop: flags.gapThroughStop ?? false,
      context: held.context,
    });
    day.realizedInr += exitReason === 'DATA_GAP' ? 0 : netPnlInr;
    if (config.exits.cooldownSeconds > 0) {
      day.cooldownUntil = exitTime + config.exits.cooldownSeconds * 1_000;
    }
    position = undefined;
  };

  /** Fills a pending entry at this bar's open, then checks the bracket against the rest of the bar. */
  const fill = (entry: PendingEntry, time: number): void => {
    const bars = new Map((legBars(session, entry.optionType, entry.strike) ?? []).map((bar) => [bar.time, bar]));
    const bar = bars.get(time);
    if (bar === undefined) {
      drop('NO_OPTION_DATA');
      return;
    }
    // Live: LIMIT at ask × (1 + buffer), sized and bracketed off the limit, cancelled after ORDER_TIMEOUT_MS.
    // The quote at the signal bar's close is the next bar's open, so the order fills there at the ask.
    const entryPrice = ask(bar.open);
    const entryLimit = roundUpToTick(entryPrice * (1 + config.entryLimitBufferPct / 100), tick);
    const bracket = bracketLevels({
      entryReference: entryLimit,
      stopLossPct: config.exits.stopLossPct,
      targetRr: config.exits.targetRr,
      tickSize: tick,
      trailingJumpPct: config.exits.trailingJumpPct,
    });
    if (bracket === undefined) {
      drop('BRACKET_UNREPRESENTABLE');
      return;
    }
    const targetPrice = config.noTarget === true
      ? Infinity
      : config.exits.runnerMode
      ? roundDownToTick(bracket.entryReference + Math.max(10 * bracket.riskPerUnit, bracket.entryReference * 5), tick)
      : bracket.targetPrice;
    const capital = Math.max(0, config.capital.inr + day.realizedInr);
    const sizing = sizePosition({
      capitalInr: capital,
      maxRiskPerTradePct: config.capital.maxRiskPerTradePct,
      availableFundsInr: capital,
      entryReference: bracket.entryReference,
      stopLossPrice: bracket.stopLossPrice,
      lotSize: session.lotSize,
      maxLotsPerOrder: config.capital.maxLotsPerOrder,
      // Sized on the all-in loss when that budget is on, so the replay risks what the live gate would allow (OTA-311).
      ...(config.capital.allInRiskPolicy === 'enforce'
        ? {
            perLotRiskInr: allInAdverseLossInr({
              quantity: session.lotSize,
              entryPrice: bracket.entryReference,
              stopPrice: bracket.stopLossPrice,
              costs,
              tickSize: tick,
              exchangeSegment: optionSegment,
            }),
          }
        : {}),
    });
    if (sizing.lots < 1) {
      drop('RISK_BUDGET_TOO_SMALL');
      return;
    }
    // The live pre-trade gate itself, fed the replay's day book. One position at a time, so nothing else is open.
    const verdict = evaluatePreTrade({
      side: 'BUY',
      entryReference: bracket.entryReference,
      stopLossPrice: bracket.stopLossPrice,
      targetPrice,
      lots: sizing.lots,
      lotSize: session.lotSize,
      maxLotsPerOrder: config.capital.maxLotsPerOrder,
      maxRiskInr: sizing.riskBudgetInr,
      ...(config.capital.allInRiskPolicy === 'enforce'
        ? {
            allInRiskInr: allInAdverseLossInr({
              quantity: sizing.quantity,
              entryPrice: bracket.entryReference,
              stopPrice: bracket.stopLossPrice,
              costs,
              tickSize: tick,
              exchangeSegment: optionSegment,
            }),
          }
        : {}),
      availableFundsInr: capital,
      nowMs: time,
      minuteOfDay: istParts(time).minuteOfDay,
      entryStartMinute: config.strategy.entryStartMinute,
      entryEndMinute: config.strategy.entryEndMinute,
      isExpiryDay: session.expiry === session.date,
      expiryDayCutoffMinute: config.expiryDayEntryCutoffMinute,
      // Live engages the kill switch on a daily-loss breach, so the breach also reads as an active kill switch.
      killSwitchActive: day.realizedInr <= -dailyLossLimitInr,
      dailyPnlInr: day.realizedInr,
      dailyLossLimitInr,
      realizedPnlInr: day.realizedInr,
      openRiskInr: 0,
      tradesToday: day.trades,
      maxTradesPerDay: config.capital.maxTradesPerDay,
      openPositions: 0,
      maxOpenPositions: 1,
      cooldownUntilMs: day.cooldownUntil > 0 ? day.cooldownUntil : undefined,
      // Bars are complete by construction; staleness is a live-feed failure the replay cannot have.
      spotTickAgeMs: 0,
      optionQuoteAgeMs: 0,
      staleMs: 1,
    });
    if (!verdict.approved) {
      drop(verdict.violations[0]?.code ?? 'RISK_REJECTED');
      return;
    }
    day.trades += 1;
    const held: HeldPosition = {
      ...entry,
      bars,
      entryTime: time,
      entryLimit,
      entryPrice,
      initialStopPrice: bracket.stopLossPrice,
      stopLossPrice: bracket.stopLossPrice,
      targetPrice,
      trailingJump: bracket.trailingJump,
      highWaterMark: entryPrice,
      lots: sizing.lots,
      quantity: sizing.quantity,
      riskInr: Number(sizing.riskInr.toFixed(2)),
      lastMark: bar.open,
      flaggedExit: undefined,
      flaggedIsStop: false,
      trail: OPEN_TRAIL,
      trailPosition: {
        entryPrice,
        initialStop: bracket.stopLossPrice,
        side: entry.optionType === 'CE' ? 1 : -1,
        entryTime: time,
        barMs,
        halfSpreadPct: costs.halfSpreadPct,
        chargesPerUnit: roundTripChargesInr({ quantity: sizing.quantity, buyPrice: entryPrice, sellPrice: entryPrice, exchangeSegment: optionSegment }) / sizing.quantity,
      },
      premiumSeries: legBars(session, entry.optionType, entry.strike) ?? [],
    };
    position = held;
    step(held, time, true);
  };

  /** Exit checks for one option bar. On the entry bar the open is already used by the fill. */
  const step = (held: HeldPosition, time: number, entryBar: boolean): void => {
    const bar = held.bars.get(time);
    if (bar === undefined) {
      // No print for the held strike: the replay cannot price this bar, so the trade leaves the sample.
      close(held, time, bid(held.lastMark), 'DATA_GAP');
      return;
    }
    if (!entryBar) {
      if (bar.open <= held.stopLossPrice) {
        close(held, time, stopFill(bar.open), stopReason(held), { gapThroughStop: bar.open < held.stopLossPrice });
        return;
      }
      if (bid(bar.open) >= held.targetPrice) {
        close(held, time, held.targetPrice, 'TARGET');
        return;
      }
      const minute = istParts(time).minuteOfDay;
      const forced: ReplayExitReason | undefined =
        held.flaggedExit ??
        (minute >= config.exits.flattenByMinute
          ? 'EOD_FLATTEN'
          : time - held.entryTime >= config.exits.maxHoldMinutes * 60_000
            ? 'TIME_STOP'
            : undefined);
      if (forced !== undefined) {
        close(held, time, held.flaggedIsStop ? stopFill(bar.open) : bid(bar.open), forced);
        return;
      }
    }
    const hitStop = bar.low <= held.stopLossPrice;
    const hitTarget = bid(bar.high) >= held.targetPrice;
    if (hitStop) {
      // A 5-minute bar does not say which side traded first. The stop is assumed first.
      close(held, time, stopFill(held.stopLossPrice), stopReason(held), { ambiguousBar: hitTarget });
      return;
    }
    if (hitTarget) {
      close(held, time, held.targetPrice, 'TARGET');
      return;
    }
    held.lastMark = bar.close;
    // The trailing stop moves on this bar's high but takes effect from the next bar, never inside this one.
    if (config.trail === undefined && held.trailingJump !== undefined && held.trailingJump > 0) {
      held.highWaterMark = Math.max(held.highWaterMark, bar.high);
      held.stopLossPrice = calculateTrailingStop({
        entryPrice: held.entryPrice,
        initialStopPrice: held.initialStopPrice,
        currentStopPrice: held.stopLossPrice,
        highWaterMark: held.highWaterMark,
        trailingJump: held.trailingJump,
        breakevenAtRr: config.exits.breakevenAtRr,
        tickSize: tick,
      });
    }
  };

  for (const spotBar of session.spot) {
    const time = spotBar.time;
    if (pending !== undefined) {
      const entry = pending;
      pending = undefined;
      fill(entry, time);
    } else if (position !== undefined) {
      step(position, time, false);
    }

    history.push(spotBar);
    const closeTime = time + barMs;
    const closeMinute = istParts(closeTime).minuteOfDay;

    if (position !== undefined) {
      const held: HeldPosition = position;
      const heldDirection: Direction = held.optionType === 'CE' ? 'BULLISH' : 'BEARISH';
      if (day.realizedInr + (held.lastMark - held.entryPrice) * held.quantity <= -dailyLossLimitInr) {
        held.flaggedExit = 'DAILY_LOSS';
      } else if (config.trail !== undefined && applyTrail(config.trail, held, history, spotBar, tick)) {
        held.flaggedExit = 'TRAILING_STOP';
        held.flaggedIsStop = true;
      } else if (config.structureExit && structureTurnedAgainst(marketStructure(history), heldDirection)) {
        held.flaggedExit = 'STRUCTURE_BREAK';
      }
      continue;
    }
    if (closeMinute < config.strategy.entryStartMinute || closeMinute >= config.strategy.entryEndMinute) {
      continue;
    }
    const signal = strategySession.evaluate(history, params);
    if (observer !== undefined) {
      observer.onEntryBar(strategySession.candidates(history, params), signal);
    }
    if (signal === undefined) {
      continue;
    }
    signals += 1;
    if (!expiryWithinLimits(session, config)) {
      drop('EXPIRY_OUT_OF_RANGE');
      continue;
    }
    const context = marketContext(history);
    if (config.contextGate && !contextVerdict(context, signal.direction, 'NEUTRAL').ok) {
      drop('CONTEXT_REJECTED');
      continue;
    }
    const optionType = directionToOptionType(signal.direction);
    const atm = nearestAtmStrike(signal.spot, sessionStrikes(session, optionType));
    if (atm === undefined) {
      drop('NO_OPTION_DATA');
      continue;
    }
    const ivBucket = ivBucketFor(ivHistory[optionType], istParts(signal.barTime).minuteOfDay, atmIvAt(session, optionType, signal.barTime, signal.spot));
    pending = {
      strategy: signal.strategy ?? 'unknown',
      direction: signal.direction,
      optionType,
      strike: targetEntryStrike(atm, session.strikeStep, signal.direction, config.strikeOffsetSteps),
      signalBarTime: signal.barTime,
      context: tradeContext(context, signal.direction, signal.barTime, session, history, ivBucket),
    };
  }

  if (pending !== undefined) {
    drop('NO_NEXT_BAR');
  }
  if (position !== undefined) {
    const held: HeldPosition = position;
    const last = session.spot[session.spot.length - 1];
    close(held, last === undefined ? held.entryTime : last.time + barMs, bid(held.lastMark), 'EOD_FLATTEN');
  }
  return { trades, signals };
}


import type { Candle, Direction, Signal } from '../domain/types.js';
import { ema, superTrend, adaptiveSuperTrend } from '../market/indicators.js';
import { istParts } from '../time/ist.js';
import { previousDayBreak } from './levelBreak.js';
import { evaluateOrbSupertrend, openingRangeCross, openingRangeWindow, sessionRange, type OrbSupertrendParams } from './orbSupertrend.js';

export const POSTURES = ['scout', 'aligned', 'confirmed'] as const;
export type StrategyPosture = (typeof POSTURES)[number];

export const POSTURE_LABELS: Record<StrategyPosture, string> = {
  scout: 'scout (aggressive)',
  aligned: 'aligned (balanced)',
  confirmed: 'confirmed (protective)',
};

export const STRATEGY_CATALOG = [
  { id: 'range', label: 'Range break' },
  { id: 'trend', label: 'Trend flip' },
  { id: 'ema_cross', label: 'EMA cross' },
  { id: 'momentum', label: 'Momentum break' },
  { id: 'continuation', label: 'Trend continuation' },
  // Research: off unless named, so an untested family never trades because a config listed no strategies.
  { id: 'prev_day', label: 'Previous-day break', research: true },
] as const;

export type StrategyId = (typeof STRATEGY_CATALOG)[number]['id'];

export interface StrategyChoice {
  readonly id: StrategyId;
  readonly label: string;
  readonly on: boolean;
}

export interface StrategySessionView {
  readonly posture: StrategyPosture;
  readonly strategies: readonly StrategyChoice[];
}

/**
 * Which posture and which strategies may fire. Shared by every underlying so one key changes the session.
 * Range break is tried before trend flip, so when both fire on the same bar the opening-range signal wins.
 */
export class StrategySession {
  private posture: StrategyPosture;
  private readonly enabled: Set<StrategyId>;

  constructor(initial: StrategyPosture = 'aligned', initialStrategies?: readonly StrategyId[]) {
    this.posture = initial;
    this.enabled = new Set<StrategyId>(
      initialStrategies !== undefined && initialStrategies.length > 0
        ? initialStrategies
        : STRATEGY_CATALOG.filter((row) => !('research' in row)).map((row) => row.id),
    );
  }

  cyclePosture(): string {
    const index = POSTURES.indexOf(this.posture);
    this.posture = POSTURES[(index + 1) % POSTURES.length] ?? 'aligned';
    return `${POSTURE_LABELS[this.posture]} · ${this.armedText()}`;
  }

  setPosture(posture: StrategyPosture): void {
    this.posture = posture;
  }

  toggle(id: StrategyId): string {
    if (this.enabled.has(id)) {
      this.enabled.delete(id);
    } else {
      this.enabled.add(id);
    }
    const label = STRATEGY_CATALOG.find((row) => row.id === id)?.label ?? id;
    const state = this.enabled.has(id) ? 'on' : 'off';
    return `${label} ${state} · ${this.armedText()}`;
  }

  view(): StrategySessionView {
    return {
      posture: this.posture,
      strategies: STRATEGY_CATALOG.map((row) => ({ id: row.id, label: row.label, on: this.enabled.has(row.id) })),
    };
  }

  evaluate(bars: readonly Candle[], params: OrbSupertrendParams): Signal | undefined {
    for (const row of STRATEGY_CATALOG) {
      if (!this.enabled.has(row.id)) {
        continue;
      }
      const signal = this.dispatchSignal(row.id, bars, params);
      if (signal !== undefined) {
        return { ...signal, strategy: row.id };
      }
    }
    return undefined;
  }

  /**
   * Every enabled family's signal on the same bars, in catalogue order, before first-match. Research only (OTA-307):
   * the live engine keeps `evaluate`, which returns the first hit. Each entry carries the family that produced it.
   */
  candidates(bars: readonly Candle[], params: OrbSupertrendParams): Array<Signal & { readonly strategy: StrategyId }> {
    const found: Array<Signal & { readonly strategy: StrategyId }> = [];
    for (const row of STRATEGY_CATALOG) {
      if (!this.enabled.has(row.id)) {
        continue;
      }
      const signal = this.dispatchSignal(row.id, bars, params);
      if (signal !== undefined) {
        found.push({ ...signal, strategy: row.id });
      }
    }
    return found;
  }

  private dispatchSignal(id: StrategyId, bars: readonly Candle[], params: OrbSupertrendParams): Signal | undefined {
    switch (id) {
      case 'range': return rangeSignal(bars, params, this.posture);
      case 'trend': return trendSignal(bars, params, this.posture);
      case 'ema_cross': return emaCrossSignal(bars, params, this.posture);
      case 'momentum': return momentumSignal(bars, params, this.posture);
      case 'continuation': return continuationSignal(bars, params, this.posture);
      case 'prev_day': return previousDayBreak(bars, params, this.posture === 'scout');
    }
  }

  private armedText(): string {
    const armed = STRATEGY_CATALOG.filter((row) => this.enabled.has(row.id)).map((row) => row.label);
    return armed.length === 0 ? 'no strategy armed' : armed.join(', ');
  }
}

function tag(signal: Signal, label: string): Signal {
  return { ...signal, reasons: [`${label} (${signal.reasons[0] ?? 'signal'})`, ...signal.reasons.slice(1)] };
}

/**
 * True when every bar belongs to the same IST session as `last`. The scout families compare the last bar with the bars
 * just before it. Without this, the first bar of a day is compared with yesterday's close, and an overnight gap alone
 * reads as a momentum break, an EMA cross or a continuation.
 */
function sameSession(last: Candle, ...others: readonly Candle[]): boolean {
  const day = istParts(last.time).date;
  return others.every((other) => istParts(other.time).date === day);
}

function inWindow(bar: Candle, params: OrbSupertrendParams): boolean {
  const minute = istParts(bar.time).minuteOfDay;
  return minute >= params.entryStartMinute && minute < params.entryEndMinute;
}

function rangeSignal(bars: readonly Candle[], params: OrbSupertrendParams, posture: StrategyPosture): Signal | undefined {
  if (posture === 'aligned') {
    const signal = evaluateOrbSupertrend(bars, params);
    return signal === undefined ? undefined : tag(signal, 'Range break');
  }
  return posture === 'scout' ? rangeScout(bars, params) : rangeConfirmed(bars, params);
}

function rangeScout(bars: readonly Candle[], params: OrbSupertrendParams): Signal | undefined {
  const cross = openingRangeCross(bars, params);
  const last = bars[bars.length - 1];
  return cross === undefined || last === undefined
    ? undefined
    : tag(plainSignal(params, last, cross.direction, `ORB cross ${cross.level}`), 'Range break');
}

function rangeConfirmed(bars: readonly Candle[], params: OrbSupertrendParams): Signal | undefined {
  const prior = bars.slice(0, -1);
  const crossed = evaluateOrbSupertrend(prior, params);
  const last = bars[bars.length - 1];
  if (crossed === undefined || last === undefined || !inWindow(last, params)) {
    return undefined;
  }
  const day = istParts(last.time).date;
  const range = sessionRange(bars, day, openingRangeWindow(params));
  if (range === undefined) {
    return undefined;
  }
  const held = crossed.direction === 'BULLISH' ? last.close > range.high : last.close < range.low;
  if (!held || !trendConfluence(bars, params, crossed.direction)) {
    return undefined;
  }
  return tag(
    { ...crossed, barTime: last.time, spot: last.close, reasons: [`held beyond the range at ${last.close}`, ...crossed.reasons.slice(1)] },
    'Range break',
  );
}

function trendConfluence(bars: readonly Candle[], params: OrbSupertrendParams, direction: Direction): boolean {
  const trend = superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  const closes = bars.map((bar) => bar.close);
  const fast = ema(closes, params.emaFast);
  const slow = ema(closes, params.emaSlow);
  return trend !== undefined && fast !== undefined && slow !== undefined
    && (direction === 'BULLISH' ? trend.trend === 'UP' && fast > slow : trend.trend === 'DOWN' && fast < slow);
}

function plainSignal(params: OrbSupertrendParams, bar: Candle, direction: Direction, detail: string): Signal {
  return { underlying: params.underlying, direction, barTime: bar.time, spot: bar.close, reasons: [detail] };
}

function trendSignal(bars: readonly Candle[], params: OrbSupertrendParams, posture: StrategyPosture): Signal | undefined {
  const last = bars[bars.length - 1];
  const trend = posture === 'scout'
    ? adaptiveSuperTrend(bars, params.supertrendPeriod, params.supertrendMultiplier)
    : superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  if (last === undefined || trend === undefined || !inWindow(last, params)) {
    return undefined;
  }
  if (posture === 'scout') {
    const maxBars = params.maxBarsSinceFlip ?? 0;
    const minDistance = params.minDistanceAtr ?? 0.5;
    if ((maxBars > 0 && trend.barsSinceFlip > maxBars) || trend.distanceAtr < minDistance) {
      return undefined;
    }
    return trendSignalOf(params, last, trend, 'adaptive flip');
  }
  const closes = bars.map((bar) => bar.close);
  const fast = ema(closes, params.emaFast);
  const slow = ema(closes, params.emaSlow);
  const agrees = fast !== undefined && slow !== undefined && (trend.trend === 'UP' ? fast > slow : fast < slow);
  if (!agrees) {
    return undefined;
  }
  if (posture === 'aligned') {
    return trend.flipped ? trendSignalOf(params, last, trend, 'flip with EMA') : undefined;
  }
  return trendConfirmed(bars, params, last, trend);
}

function trendConfirmed(
  bars: readonly Candle[],
  params: OrbSupertrendParams,
  last: Candle,
  trend: { trend: 'UP' | 'DOWN'; flipped: boolean; barsSinceFlip: number; distanceAtr: number; flipBarTime: number },
): Signal | undefined {
  const prior = superTrend(bars.slice(0, -1), params.supertrendPeriod, params.supertrendMultiplier);
  if (prior === undefined || !prior.flipped || prior.trend !== trend.trend || trend.flipped) {
    return undefined;
  }
  const day = istParts(last.time).date;
  const range = sessionRange(bars, day, openingRangeWindow(params));
  if (range === undefined) {
    return undefined;
  }
  const beyond = trend.trend === 'UP' ? last.close > range.high : last.close < range.low;
  return beyond ? trendSignalOf(params, last, trend, 'flip held beyond the range') : undefined;
}

function trendSignalOf(
  params: OrbSupertrendParams,
  bar: Candle,
  trend: { trend: 'UP' | 'DOWN'; barsSinceFlip: number; distanceAtr: number; flipBarTime: number },
  detail: string,
): Signal {
  const direction: Direction = trend.trend === 'UP' ? 'BULLISH' : 'BEARISH';
  const recency = trend.barsSinceFlip === 0 ? 'exact flip' : `flip +${trend.barsSinceFlip}b`;
  return {
    underlying: params.underlying,
    direction,
    barTime: bar.time,
    spot: bar.close,
    reasons: [`Trend flip (${detail}: ${recency}, dist ${trend.distanceAtr.toFixed(2)}x ATR)`, `SuperTrend ${trend.trend}`],
    flipBarTime: trend.flipBarTime,
  };
}

function emaCrossSignal(bars: readonly Candle[], params: OrbSupertrendParams, posture: StrategyPosture): Signal | undefined {
  const last = bars[bars.length - 1];
  const prev = bars[bars.length - 2];
  if (last === undefined || prev === undefined || !inWindow(last, params) || bars.length < params.emaSlow + 2) return undefined;
  if (!sameSession(last, prev)) return undefined;
  const closes = bars.map((b) => b.close);
  const fast = ema(closes, params.emaFast);
  const slow = ema(closes, params.emaSlow);
  const prevFast = ema(closes.slice(0, -1), params.emaFast);
  const prevSlow = ema(closes.slice(0, -1), params.emaSlow);
  if (fast === undefined || slow === undefined || prevFast === undefined || prevSlow === undefined) return undefined;
  const bullish = fast > slow && prevFast <= prevSlow;
  const bearish = fast < slow && prevFast >= prevSlow;
  if (!bullish && !bearish) return undefined;
  const direction: Direction = bullish ? 'BULLISH' : 'BEARISH';
  if (posture === 'scout') {
    return tag(plainSignal(params, last, direction, `EMA${params.emaFast} cross EMA${params.emaSlow} (${direction})`), 'EMA cross');
  }
  const trend = superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  if (trend === undefined || (bullish ? trend.trend !== 'UP' : trend.trend !== 'DOWN')) return undefined;
  return tag(plainSignal(params, last, direction, `EMA cross with SuperTrend ${trend.trend}`), 'EMA cross');
}

function momentumSignal(bars: readonly Candle[], params: OrbSupertrendParams, posture: StrategyPosture): Signal | undefined {
  const last = bars[bars.length - 1];
  const prev = bars[bars.length - 2];
  if (last === undefined || prev === undefined || !inWindow(last, params) || bars.length < 5) return undefined;
  const lookback = bars.slice(-4, -1);
  if (!sameSession(last, ...lookback)) return undefined;
  const high = Math.max(...lookback.map((b) => b.high));
  const low = Math.min(...lookback.map((b) => b.low));
  const bullish = last.close > high && prev.close <= high;
  const bearish = last.close < low && prev.close >= low;
  if (!bullish && !bearish) return undefined;
  const direction: Direction = bullish ? 'BULLISH' : 'BEARISH';
  if (posture === 'scout') {
    return tag(plainSignal(params, last, direction, `3-bar ${bullish ? 'high ' + high : 'low ' + low} break`), 'Momentum break');
  }
  const trend = superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  if (trend === undefined || (bullish ? trend.trend !== 'UP' : trend.trend !== 'DOWN')) return undefined;
  return tag(plainSignal(params, last, direction, `Momentum break with SuperTrend ${trend.trend}`), 'Momentum break');
}

function continuationSignal(bars: readonly Candle[], params: OrbSupertrendParams, posture: StrategyPosture): Signal | undefined {
  const last = bars[bars.length - 1];
  const prev = bars[bars.length - 2];
  if (last === undefined || prev === undefined || !inWindow(last, params) || bars.length < 5) return undefined;
  const trend = posture === 'scout'
    ? adaptiveSuperTrend(bars, params.supertrendPeriod, params.supertrendMultiplier)
    : superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  if (trend === undefined || trend.barsSinceFlip < 1 || !sameSession(last, prev)) return undefined;
  const bullish = trend.trend === 'UP' && prev.close < last.close && last.close > prev.high;
  const bearish = trend.trend === 'DOWN' && prev.close > last.close && last.close < prev.low;
  if (!bullish && !bearish) return undefined;
  const direction: Direction = bullish ? 'BULLISH' : 'BEARISH';
  if (posture === 'scout') {
    return tag(plainSignal(params, last, direction, `Pullback bounce in ${trend.trend} trend`), 'Trend continuation');
  }
  const closes = bars.map((b) => b.close);
  const fast = ema(closes, params.emaFast);
  const slow = ema(closes, params.emaSlow);
  const emaAgrees = fast !== undefined && slow !== undefined && (bullish ? fast > slow : fast < slow);
  if (!emaAgrees) return undefined;
  return tag(plainSignal(params, last, direction, `Trend continuation (${trend.trend} + EMA)`), 'Trend continuation');
}


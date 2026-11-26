import type { Candle, Direction, Signal } from '../domain/types.js';
import { istParts } from '../time/ist.js';
import { barsInWindow } from '../time/sessionCoverage.js';
import { ema, superTrend } from '../market/indicators.js';

export interface OrbSupertrendParams {
  readonly underlying: string;
  readonly orbMinutes: number;
  /** Bar size, so an opening range missing a bar can be told from a complete one. */
  readonly barMinutes: number;
  readonly supertrendPeriod: number;
  readonly supertrendMultiplier: number;
  readonly emaFast: number;
  readonly emaSlow: number;
  /** Signal bars must open inside [entryStartMinute, entryEndMinute) IST. */
  readonly entryStartMinute: number;
  readonly entryEndMinute: number;
  /** Opening range begins at the first regular-session minute. */
  readonly sessionOpenMinute: number;
  readonly maxBarsSinceFlip?: number | undefined;
  readonly minDistanceAtr?: number | undefined;
}

/**
 * High and low of the bars on one IST date that open within [fromMinute, toMinute). Undefined unless every bar of
 * that window is present: a range built from part of it is a different, narrower level.
 */
export function sessionRange(
  bars: readonly Candle[],
  dateKey: string,
  window: { readonly fromMinute: number; readonly toMinute: number; readonly barMinutes: number },
): { high: number; low: number } | undefined {
  let high = Number.NEGATIVE_INFINITY;
  let low = Number.POSITIVE_INFINITY;
  const opens = new Set<number>();
  for (const bar of bars) {
    const parts = istParts(bar.time);
    if (parts.date === dateKey && parts.minuteOfDay >= window.fromMinute && parts.minuteOfDay < window.toMinute) {
      high = Math.max(high, bar.high);
      low = Math.min(low, bar.low);
      opens.add(parts.minuteOfDay);
    }
  }
  const expectedBars = barsInWindow(window.fromMinute, window.toMinute, window.barMinutes);
  return opens.size === expectedBars ? { high, low } : undefined;
}

/** The opening-range window of `params`. */
export function openingRangeWindow(params: OrbSupertrendParams): { fromMinute: number; toMinute: number; barMinutes: number } {
  return { fromMinute: params.sessionOpenMinute, toMinute: params.sessionOpenMinute + params.orbMinutes, barMinutes: params.barMinutes };
}

/**
 * Opening-range breakout confirmed by SuperTrend direction and EMA alignment,
 * evaluated only on closed bars. A signal fires on the bar that crosses the
 * opening-range boundary; a bar that is already beyond it does not re-fire.
 *
 * Returns undefined rather than a weak signal whenever inputs are insufficient.
 */
export function evaluateOrbSupertrend(bars: readonly Candle[], params: OrbSupertrendParams): Signal | undefined {
  const prepared = prepareBreak(bars, params);
  if (prepared === undefined) {
    return undefined;
  }
  const cross = closeCross(prepared.close, prepared.previousClose, prepared.orbHigh, prepared.orbLow);
  if (cross === undefined) {
    return undefined;
  }
  const closes = bars.map((bar) => bar.close);
  const fast = ema(closes, params.emaFast);
  const slow = ema(closes, params.emaSlow);
  const trend = superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
  if (fast === undefined || slow === undefined || trend === undefined || !confluenceAgrees(cross, trend.trend, fast, slow)) {
    return undefined;
  }
  const broken = cross === 'BULLISH' ? prepared.orbHigh : prepared.orbLow;
  const side = cross === 'BULLISH' ? 'high' : 'low';
  const emaSign = cross === 'BULLISH' ? '>' : '<';
  return {
    underlying: params.underlying,
    direction: cross,
    barTime: prepared.barTime,
    spot: prepared.close,
    reasons: [
      `ORB ${side} ${broken} broken by close ${prepared.close}`,
      `SuperTrend ${trend.trend} (line ${trend.line.toFixed(2)})`,
      `EMA${params.emaFast} ${fast.toFixed(2)} ${emaSign} EMA${params.emaSlow} ${slow.toFixed(2)}`,
    ],
  };
}

/** Close that steps through the opening-range high or low. No indicator check. */
export function openingRangeCross(bars: readonly Candle[], params: OrbSupertrendParams): { direction: Direction; level: number } | undefined {
  const prepared = prepareBreak(bars, params);
  if (prepared === undefined) {
    return undefined;
  }
  const direction = closeCross(prepared.close, prepared.previousClose, prepared.orbHigh, prepared.orbLow);
  if (direction === undefined) {
    return undefined;
  }
  return { direction, level: direction === 'BULLISH' ? prepared.orbHigh : prepared.orbLow };
}

interface PreparedBreak {
  readonly close: number;
  readonly previousClose: number;
  readonly orbHigh: number;
  readonly orbLow: number;
  readonly barTime: number;
}

function prepareBreak(bars: readonly Candle[], params: OrbSupertrendParams): PreparedBreak | undefined {
  const signalBar = bars[bars.length - 1];
  const previousBar = bars[bars.length - 2];
  if (signalBar === undefined || previousBar === undefined) {
    return undefined;
  }
  const signalParts = istParts(signalBar.time);
  const previousParts = istParts(previousBar.time);
  if (signalParts.date !== previousParts.date) {
    return undefined;
  }
  if (signalParts.minuteOfDay < params.entryStartMinute || signalParts.minuteOfDay >= params.entryEndMinute) {
    return undefined;
  }
  const orbEndMinute = params.sessionOpenMinute + params.orbMinutes;
  if (signalParts.minuteOfDay < orbEndMinute) {
    return undefined;
  }
  const range = sessionRange(bars, signalParts.date, openingRangeWindow(params));
  if (range === undefined) {
    return undefined;
  }
  return {
    close: signalBar.close,
    previousClose: previousBar.close,
    orbHigh: range.high,
    orbLow: range.low,
    barTime: signalBar.time,
  };
}

function closeCross(close: number, previousClose: number, orbHigh: number, orbLow: number): Direction | undefined {
  if (close > orbHigh && previousClose <= orbHigh) {
    return 'BULLISH';
  }
  if (close < orbLow && previousClose >= orbLow) {
    return 'BEARISH';
  }
  return undefined;
}

function confluenceAgrees(direction: Direction, trend: 'UP' | 'DOWN', fast: number, slow: number): boolean {
  if (direction === 'BULLISH') {
    return trend === 'UP' && fast > slow;
  }
  return trend === 'DOWN' && fast < slow;
}

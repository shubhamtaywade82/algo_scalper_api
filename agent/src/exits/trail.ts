import type { Candle } from '../domain/types.js';
import { alma, ema, hma, sma, superTrend, wilderAtr } from '../market/indicators.js';
import {
  acceptedSwingLow,
  donchianLow,
  latestFractalLow,
  mirrorCandles,
  protectedLow,
  psarAfter,
  windowHigh,
  type PsarParams,
} from '../market/stopLines.js';

/**
 * Trailing exits for a bought option, as a pure state machine (docs/TRAILING_STOPS.md §4). Every level is
 * recomputed from closed bars, so a resent bar or a replayed run gives the same answer, and a level never loosens.
 */

export type TrailSeries = 'UNDERLYING' | 'PREMIUM';
export type MovingAverage = 'EMA' | 'SMA' | 'ALMA' | 'HMA';

export type TrailSpec =
  | { readonly kind: 'ATR'; readonly period: number; readonly mult: number; readonly activationR: number }
  | { readonly kind: 'CHANDELIER'; readonly series: TrailSeries; readonly lookback: number; readonly period: number; readonly mult: number }
  | { readonly kind: 'SUPERTREND'; readonly series: TrailSeries; readonly period: number; readonly mult: number }
  | ({ readonly kind: 'PSAR'; readonly series: TrailSeries } & PsarParams)
  | { readonly kind: 'MA_CROSS'; readonly series: TrailSeries; readonly ma: MovingAverage; readonly period: number }
  | { readonly kind: 'SWING'; readonly strength: number; readonly bufferAtr: number }
  | { readonly kind: 'FRACTAL'; readonly window: number }
  | { readonly kind: 'CHOCH'; readonly strength: number }
  | { readonly kind: 'DONCHIAN'; readonly series: TrailSeries; readonly bars: number }
  | { readonly kind: 'R_STAIRCASE'; readonly activationR: number; readonly stepR: number; readonly netBreakeven: boolean }
  | { readonly kind: 'GIVEBACK'; readonly activationR: number; readonly giveback: number }
  | { readonly kind: 'TIME_DECAY'; readonly schedule: readonly { readonly uptoMinutes: number; readonly mult: number }[] }
  | { readonly kind: 'PREMIUM_ATR'; readonly period: number; readonly mult: number; readonly activationR: number }
  | { readonly kind: 'HYBRID'; readonly premium: TrailSpec; readonly underlying: TrailSpec };

/** What the trail needs to know about the position. Fixed at entry. */
export interface TrailPosition {
  readonly entryPrice: number;
  readonly initialStop: number;
  /** Underlying direction of the thesis: +1 for a CE, −1 for a PE. */
  readonly side: 1 | -1;
  /** Open time of the bar the entry filled in. */
  readonly entryTime: number;
  readonly barMs: number;
  readonly halfSpreadPct: number;
  /** Round-trip charges divided by quantity, for a net breakeven. */
  readonly chargesPerUnit: number;
}

/** Closed bars, oldest first: spot with its warmup, premium for the held strike from session open. */
export interface TrailBars {
  readonly spot: readonly Candle[];
  readonly premium: readonly Candle[];
}

export type TrailPhase = 'PENDING' | 'ACTIVE' | 'TRIGGERED';

export interface ExitIntent {
  /** TOUCH: price reached the level. CLOSE: a closed bar confirmed the exit; fill at the next open. */
  readonly kind: 'TOUCH' | 'CLOSE';
  readonly series: TrailSeries;
  readonly level: number | undefined;
}

export interface TrailState {
  readonly phase: TrailPhase;
  readonly levels: Readonly<Partial<Record<TrailSeries, number>>>;
  readonly intent: ExitIntent | undefined;
  /** Why an ATR used fewer bars than its period, or could not be computed. */
  readonly fallback: string | undefined;
}

export const OPEN_TRAIL: TrailState = { phase: 'PENDING', levels: {}, intent: undefined, fallback: undefined };

interface LegResult {
  readonly series: TrailSeries;
  /** In the leg's oriented units (higher is tighter). */
  readonly level?: number | undefined;
  readonly closeExit?: boolean;
  readonly fallback?: string | undefined;
}

/** A leg's bars turned so the position is always long: premium as is, the underlying mirrored for a PE. */
interface Oriented {
  readonly bars: readonly Candle[];
  readonly entryIndex: number;
  readonly last: number;
  /** Multiply an oriented level by this to get the real price. */
  readonly sign: 1 | -1;
}

function seriesOf(spec: TrailSpec): TrailSeries {
  switch (spec.kind) {
    case 'ATR':
    case 'SWING':
    case 'FRACTAL':
    case 'CHOCH':
      return 'UNDERLYING';
    case 'R_STAIRCASE':
    case 'GIVEBACK':
    case 'TIME_DECAY':
    case 'PREMIUM_ATR':
    case 'HYBRID':
      return 'PREMIUM';
    default:
      return spec.series;
  }
}

function activationR(spec: TrailSpec): number {
  if (spec.kind === 'HYBRID') {
    return activationR(spec.premium);
  }
  return 'activationR' in spec ? spec.activationR : 0;
}

function firstIndexAtOrAfter(bars: readonly Candle[], time: number): number {
  const index = bars.findIndex((bar) => bar.time >= time);
  return index === -1 ? bars.length : index;
}

function orient(bars: TrailBars, series: TrailSeries, position: TrailPosition): Oriented {
  const raw = series === 'PREMIUM' ? bars.premium : bars.spot;
  const sign = series === 'PREMIUM' ? 1 : position.side;
  const oriented = sign === 1 ? raw : mirrorCandles(raw);
  return { bars: oriented, entryIndex: firstIndexAtOrAfter(oriented, position.entryTime), last: oriented.length - 1, sign };
}

/** Wilder ATR at the last bar. With fewer bars than the period, uses all of them if there are at least 3. */
function lastAtr(bars: readonly Candle[], period: number): { atr: number | undefined; fallback: string | undefined } {
  const full = wilderAtr(bars, period).at(-1);
  if (full !== undefined) {
    return { atr: full, fallback: undefined };
  }
  if (bars.length >= 3) {
    return { atr: wilderAtr(bars, bars.length).at(-1), fallback: 'short_atr' };
  }
  return { atr: undefined, fallback: 'insufficient_bars' };
}

function movingAverage(kind: MovingAverage, values: readonly number[], period: number): number | undefined {
  switch (kind) {
    case 'EMA':
      return ema(values, period);
    case 'SMA':
      return sma(values, period);
    case 'ALMA':
      return alma(values, period);
    case 'HMA':
      return hma(values, period);
  }
}

/** Long-oriented: true when the last close crossed from on-or-above the average to below it. */
function crossedBelow(bars: readonly Candle[], kind: MovingAverage, period: number): boolean {
  const closes = bars.map((bar) => bar.close);
  const now = movingAverage(kind, closes, period);
  const before = movingAverage(kind, closes.slice(0, -1), period);
  const lastClose = closes.at(-1);
  const priorClose = closes.at(-2);
  if (now === undefined || before === undefined || lastClose === undefined || priorClose === undefined) {
    return false;
  }
  return priorClose >= before && lastClose < now;
}

function atrLevel(extreme: number | undefined, bars: readonly Candle[], period: number, mult: number): { level: number | undefined; fallback: string | undefined } {
  const { atr, fallback } = lastAtr(bars, period);
  return { level: extreme === undefined || atr === undefined ? undefined : extreme - mult * atr, fallback };
}

function profitLevel(spec: TrailSpec, position: TrailPosition, peak: number, bars: readonly Candle[]): LegResult {
  const risk = position.entryPrice - position.initialStop;
  const peakR = (peak - position.entryPrice) / risk;
  if (spec.kind === 'R_STAIRCASE') {
    const steps = Math.floor((peakR - spec.activationR) / spec.stepR);
    const breakeven = spec.netBreakeven ? position.chargesPerUnit + (position.entryPrice * position.halfSpreadPct) / 100 : 0;
    return { series: 'PREMIUM', level: position.entryPrice + breakeven + (spec.activationR - 1 + steps * spec.stepR) * risk };
  }
  if (spec.kind === 'GIVEBACK') {
    const peakBid = peak * (1 - position.halfSpreadPct / 100);
    return { series: 'PREMIUM', level: position.entryPrice + (1 - spec.giveback) * (peakBid - position.entryPrice) };
  }
  if (spec.kind === 'TIME_DECAY') {
    const lastTime = bars.at(-1)?.time ?? position.entryTime;
    const heldMinutes = (lastTime + position.barMs - position.entryTime) / 60_000;
    const mult = (spec.schedule.find((tier) => heldMinutes <= tier.uptoMinutes) ?? spec.schedule.at(-1))?.mult ?? 0;
    return { series: 'PREMIUM', ...atrLevel(peak, bars, 14, mult) };
  }
  return { series: 'PREMIUM' };
}

function evaluateLeg(spec: TrailSpec, position: TrailPosition, bars: TrailBars, peak: number): LegResult {
  const series = seriesOf(spec);
  const { bars: b, entryIndex: ei, last } = orient(bars, series, position);
  if (last < ei) {
    return { series };
  }
  switch (spec.kind) {
    case 'ATR':
      return { series, ...atrLevel(windowHigh(b, ei, last, Infinity), b, spec.period, spec.mult) };
    case 'CHANDELIER':
      return { series, ...atrLevel(windowHigh(b, ei, last, spec.lookback), b, spec.period, spec.mult) };
    case 'PREMIUM_ATR':
      return { series, ...atrLevel(peak, b, spec.period, spec.mult) };
    case 'SUPERTREND': {
      const state = superTrend(b, spec.period, spec.mult);
      return { series, closeExit: state !== undefined && state.flipped && state.trend === 'DOWN' };
    }
    case 'PSAR': {
      const initial = series === 'PREMIUM' ? position.initialStop : (b[ei - 1] ?? b[ei])?.low ?? Number.NaN;
      return { series, level: psarAfter(b, ei, last, initial, spec) };
    }
    case 'MA_CROSS':
      return { series, closeExit: crossedBelow(b, spec.ma, spec.period) };
    case 'SWING': {
      const swing = acceptedSwingLow(b, ei, last, spec.strength);
      const { atr, fallback } = lastAtr(b, 14);
      return { series, level: swing === undefined || atr === undefined ? undefined : swing - spec.bufferAtr * atr, fallback };
    }
    case 'FRACTAL':
      return { series, level: latestFractalLow(b, last, spec.window) };
    case 'CHOCH': {
      const level = protectedLow(b, last, spec.strength);
      return { series, closeExit: level !== undefined && (b[last]?.close ?? Infinity) < level };
    }
    case 'DONCHIAN':
      return { series, level: donchianLow(b, ei, last, spec.bars) };
    case 'HYBRID':
      return { series };
    default:
      return profitLevel(spec, position, peak, b);
  }
}

function legsOf(spec: TrailSpec): TrailSpec[] {
  return spec.kind === 'HYBRID' ? [spec.premium, spec.underlying] : [spec];
}

/** Moves each level toward the position only, and never below the initial stop on the premium. */
function ratchet(previous: number | undefined, candidate: number, sign: 1 | -1, floor: number | undefined): number {
  const floored = floor === undefined ? candidate : Math.max(candidate, floor);
  return previous === undefined ? floored : sign * Math.max(sign * previous, sign * floored);
}

/** Advances the trail after a bar close. Pure: the same state and bars always give the same result. */
export function onBarClosed(spec: TrailSpec, position: TrailPosition, state: TrailState, bars: TrailBars): TrailState {
  if (state.phase === 'TRIGGERED') {
    return state;
  }
  const sinceEntry = bars.premium.slice(firstIndexAtOrAfter(bars.premium, position.entryTime));
  if (sinceEntry.length === 0) {
    return state;
  }
  const peak = Math.max(...sinceEntry.map((bar) => bar.high));
  const peakR = (peak - position.entryPrice) / (position.entryPrice - position.initialStop);
  const activation = activationR(spec);
  if (state.phase === 'PENDING' && activation > 0 && peakR < activation) {
    return state;
  }
  const levels: Partial<Record<TrailSeries, number>> = { ...state.levels };
  let fallback = state.fallback;
  for (const leg of legsOf(spec)) {
    const result = evaluateLeg(leg, position, bars, peak);
    fallback = result.fallback ?? fallback;
    const sign = result.series === 'PREMIUM' ? 1 : position.side;
    if (result.closeExit === true) {
      return { phase: 'TRIGGERED', levels, fallback, intent: { kind: 'CLOSE', series: result.series, level: levels[result.series] } };
    }
    if (result.level !== undefined && Number.isFinite(result.level)) {
      const floor = result.series === 'PREMIUM' ? position.initialStop : undefined;
      levels[result.series] = ratchet(levels[result.series], sign * result.level, sign, floor);
    }
  }
  return { phase: 'ACTIVE', levels, fallback, intent: undefined };
}

/** Checks a price against the series' level: a bar's adverse extreme in replay, the last trade price live. */
export function onTouch(state: TrailState, series: TrailSeries, price: number, side: 1 | -1): TrailState {
  const level = state.levels[series];
  if (state.phase !== 'ACTIVE' || level === undefined) {
    return state;
  }
  const sign = series === 'PREMIUM' ? 1 : side;
  return sign * (price - level) <= 0 ? { ...state, phase: 'TRIGGERED', intent: { kind: 'TOUCH', series, level } } : state;
}

/** Stable id for reports, e.g. `PREMIUM_ATR(period=14,mult=2,activationR=0)`. */
export function specId(spec: TrailSpec): string {
  if (spec.kind === 'HYBRID') {
    return `HYBRID(${specId(spec.premium)}|${specId(spec.underlying)})`;
  }
  const fields = Object.entries(spec)
    .filter(([key]) => key !== 'kind')
    .map(([key, value]) => `${key}=${Array.isArray(value) ? value.map((tier) => `${tier.uptoMinutes}:${tier.mult}`).join('/') : String(value)}`);
  return `${spec.kind}(${fields.join(',')})`;
}

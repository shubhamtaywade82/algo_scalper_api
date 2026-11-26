import type { Candle } from '../domain/types.js';

/** Exponential moving average, seeded with the SMA of the first `period` values. Undefined until seeded. */
export function ema(values: readonly number[], period: number): number | undefined {
  if (!Number.isInteger(period) || period < 1) {
    throw new RangeError(`EMA period must be a positive integer, got ${period}`);
  }
  if (values.length < period) {
    return undefined;
  }
  const multiplier = 2 / (period + 1);
  let average = 0;
  for (let i = 0; i < period; i += 1) {
    average += values[i] ?? NaN;
  }
  average /= period;
  for (let i = period; i < values.length; i += 1) {
    average = (values[i] ?? NaN) * multiplier + average * (1 - multiplier);
  }
  return Number.isFinite(average) ? average : undefined;
}

/** Wilder ATR for each bar index; entries before `period - 1` are undefined. */
export function wilderAtr(candles: readonly Candle[], period: number): (number | undefined)[] {
  const result: (number | undefined)[] = new Array<number | undefined>(candles.length).fill(undefined);
  if (candles.length < period) {
    return result;
  }
  const trueRange: number[] = candles.map((candle, index) => {
    const previous = candles[index - 1];
    if (previous === undefined) {
      return candle.high - candle.low;
    }
    return Math.max(
      candle.high - candle.low,
      Math.abs(candle.high - previous.close),
      Math.abs(candle.low - previous.close),
    );
  });
  let atr = 0;
  for (let i = 0; i < period; i += 1) {
    atr += trueRange[i] ?? 0;
  }
  atr /= period;
  result[period - 1] = atr;
  for (let i = period; i < candles.length; i += 1) {
    atr = ((atr * (period - 1)) + (trueRange[i] ?? 0)) / period;
    result[i] = atr;
  }
  return result;
}

export type SuperTrendTrend = 'UP' | 'DOWN';

export interface SuperTrendState {
  readonly trend: SuperTrendTrend;
  /** Active SuperTrend line: the lower band in an uptrend, the upper band in a downtrend. */
  readonly line: number;
  /** True when the trend changed on the last bar. */
  readonly flipped: boolean;
  /** Number of closed bars since the most recent flip (0 on the flip bar itself). */
  readonly barsSinceFlip: number;
  /** Distance in points from current close to active SuperTrend line. */
  readonly distance: number;
  /** Distance normalized by ATR (distance / ATR). */
  readonly distanceAtr: number;
  /** Timestamp of the bar on which the flip occurred. */
  readonly flipBarTime: number;
}

/** Kaufman efficiency ratio (directional price change divided by sum of absolute bar changes). */
export function efficiencyRatio(candles: readonly Candle[], index: number, period: number): number {
  if (index < period) {
    return 0;
  }
  const current = candles[index];
  const previous = candles[index - period];
  if (current === undefined || previous === undefined) {
    return 0;
  }
  const change = Math.abs(current.close - previous.close);
  let volatility = 0;
  for (let i = index - period + 1; i <= index; i += 1) {
    const c1 = candles[i];
    const c0 = candles[i - 1];
    if (c1 !== undefined && c0 !== undefined) {
      volatility += Math.abs(c1.close - c0.close);
    }
  }
  return volatility > 0 ? Math.min(1, change / volatility) : 0;
}

interface BandState {
  readonly upper?: number;
  readonly lower?: number;
  readonly trend: SuperTrendTrend;
  readonly prevClose?: number;
}

interface BandStep {
  readonly upper: number;
  readonly lower: number;
  readonly trend: SuperTrendTrend;
  readonly flipped: boolean;
}

function stepBands(candle: Candle, mult: number, bandAtr: number, state: BandState): BandStep {
  const hl2 = (candle.high + candle.low) / 2;
  const basicUpper = hl2 + mult * bandAtr;
  const basicLower = hl2 - mult * bandAtr;
  if (state.upper === undefined || state.lower === undefined || state.prevClose === undefined) {
    return { upper: basicUpper, lower: basicLower, trend: candle.close > hl2 ? 'UP' : 'DOWN', flipped: false };
  }
  const upper = basicUpper < state.upper || state.prevClose > state.upper ? basicUpper : state.upper;
  const lower = basicLower > state.lower || state.prevClose < state.lower ? basicLower : state.lower;
  let trend = state.trend;
  if (state.trend === 'DOWN' && candle.close > upper) {
    trend = 'UP';
  } else if (state.trend === 'UP' && candle.close < lower) {
    trend = 'DOWN';
  }
  return { upper, lower, trend, flipped: state.trend !== trend };
}

function calculateSuperTrend(
  candles: readonly Candle[],
  period: number,
  multiplierFn: (index: number) => number,
): SuperTrendState | undefined {
  const atr = wilderAtr(candles, period);
  let state: BandState = { trend: 'UP' };
  let lastFlipped = false;
  let barsSinceFlip = 0;
  let flipBarTime = candles[0]?.time ?? 0;

  for (let i = 0; i < candles.length; i += 1) {
    const candle = candles[i];
    const bandAtr = atr[i];
    if (candle === undefined || bandAtr === undefined) continue;
    const step = stepBands(candle, multiplierFn(i), bandAtr, state);
    state = { upper: step.upper, lower: step.lower, trend: step.trend, prevClose: candle.close };
    lastFlipped = step.flipped;
    if (step.flipped) {
      barsSinceFlip = 0;
      flipBarTime = candle.time;
    } else if (state.prevClose !== undefined) {
      barsSinceFlip += 1;
    }
  }

  if (state.upper === undefined || state.lower === undefined || candles.length === 0) return undefined;
  const lastClose = candles[candles.length - 1]?.close ?? 0;
  const line = state.trend === 'UP' ? state.lower : state.upper;
  const lastAtr = atr[candles.length - 1] ?? 0;
  const distance = Math.abs(lastClose - line);
  const distanceAtr = lastAtr > 0 ? distance / lastAtr : 0;
  return { trend: state.trend, line, flipped: lastFlipped, barsSinceFlip, distance, distanceAtr, flipBarTime };
}

/**
 * SuperTrend over the full series, returning the state at the final bar.
 * Seeded from the first bar with a valid ATR.
 */
export function superTrend(
  candles: readonly Candle[],
  period: number,
  multiplier: number,
): SuperTrendState | undefined {
  return calculateSuperTrend(candles, period, () => multiplier);
}

/**
 * Adaptive SuperTrend: scales the multiplier with the Kaufman Efficiency Ratio. Deterministic, with no learned model.
 * Tightens bands (down to 0.75x) in clean trending moves for earlier flip entries;
 * widens bands (up to 1.5x) in choppy consolidation to filter out whipsaws.
 */
export function adaptiveSuperTrend(
  candles: readonly Candle[],
  period: number,
  baseMultiplier: number,
): SuperTrendState | undefined {
  return calculateSuperTrend(candles, period, (i) => {
    const er = efficiencyRatio(candles, i, period);
    return baseMultiplier * (1.5 - er * 0.75);
  });
}

function assertPeriod(name: string, period: number): void {
  if (!Number.isInteger(period) || period < 1) {
    throw new RangeError(`${name} period must be a positive integer, got ${period}`);
  }
}

/** Simple moving average of the last `period` values. Undefined until the window is full. */
export function sma(values: readonly number[], period: number): number | undefined {
  assertPeriod('SMA', period);
  if (values.length < period) {
    return undefined;
  }
  let sum = 0;
  for (let i = values.length - period; i < values.length; i += 1) {
    sum += values[i] ?? NaN;
  }
  return Number.isFinite(sum) ? sum / period : undefined;
}

/** Linearly weighted moving average of the last `period` values, newest weighted `period`. */
export function wma(values: readonly number[], period: number): number | undefined {
  assertPeriod('WMA', period);
  if (values.length < period) {
    return undefined;
  }
  const start = values.length - period;
  let sum = 0;
  for (let i = 0; i < period; i += 1) {
    sum += (i + 1) * (values[start + i] ?? NaN);
  }
  const value = sum / ((period * (period + 1)) / 2);
  return Number.isFinite(value) ? value : undefined;
}

/** Hull moving average: WMA over sqrt(n) bars of 2·WMA(n/2) − WMA(n). Needs n + sqrt(n) − 1 values. */
export function hma(values: readonly number[], period: number): number | undefined {
  assertPeriod('HMA', period);
  const half = Math.max(1, Math.floor(period / 2));
  const root = Math.max(1, Math.floor(Math.sqrt(period)));
  if (values.length < period + root - 1) {
    return undefined;
  }
  const raw: number[] = [];
  for (let end = values.length - root + 1; end <= values.length; end += 1) {
    const window = values.slice(0, end);
    raw.push(2 * (wma(window, half) ?? NaN) - (wma(window, period) ?? NaN));
  }
  return wma(raw, root);
}

/** Arnaud Legoux moving average: Gaussian weights centred at `offset` of the window (0 = oldest). */
export function alma(values: readonly number[], period: number, offset = 0.85, sigma = 6): number | undefined {
  assertPeriod('ALMA', period);
  if (values.length < period) {
    return undefined;
  }
  const centre = offset * (period - 1);
  const width = period / sigma;
  const start = values.length - period;
  let weighted = 0;
  let weights = 0;
  for (let i = 0; i < period; i += 1) {
    const weight = Math.exp(-((i - centre) ** 2) / (2 * width * width));
    weighted += weight * (values[start + i] ?? NaN);
    weights += weight;
  }
  const value = weighted / weights;
  return Number.isFinite(value) ? value : undefined;
}

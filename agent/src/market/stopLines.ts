import type { Candle } from '../domain/types.js';

/**
 * Stop lines for a long position. A short is handled by the caller through `mirrorCandles`: the line computed on
 * mirrored bars, negated, is the short's line. One implementation per rule keeps long and short exactly symmetric.
 */

/** Negates prices so a falling market reads as a rising one. High and low swap. Mirroring twice is the identity. */
export function mirrorCandles(bars: readonly Candle[]): Candle[] {
  return bars.map((bar) => ({ ...bar, open: -bar.open, high: -bar.low, low: -bar.high, close: -bar.close }));
}

/**
 * A pivot low at `i`: lower than the `strength` lows on its left, and on its right lower (`strict`) or not higher.
 * Known only once the right-side bars have closed, so the caller must not look at `i` before bar `i + strength`.
 */
export function isPivotLow(bars: readonly Candle[], i: number, strength: number, strict: boolean): boolean {
  const low = bars[i]?.low ?? Number.NaN;
  for (let k = 1; k <= strength; k += 1) {
    const right = bars[i + k]?.low ?? -Infinity;
    if (!(low < (bars[i - k]?.low ?? -Infinity)) || !(strict ? low < right : low <= right)) {
      return false;
    }
  }
  return true;
}

export function isPivotHigh(bars: readonly Candle[], i: number, strength: number, strict: boolean): boolean {
  const high = bars[i]?.high ?? Number.NaN;
  for (let k = 1; k <= strength; k += 1) {
    const right = bars[i + k]?.high ?? Infinity;
    if (!(high > (bars[i - k]?.high ?? Infinity)) || !(strict ? high > right : high >= right)) {
      return false;
    }
  }
  return true;
}

/** Lowest low over the last `count` bars ending at `last`, never reaching before `from`. */
export function donchianLow(bars: readonly Candle[], from: number, last: number, count: number): number | undefined {
  let lowest: number | undefined;
  for (let i = Math.max(from, last - count + 1); i <= last; i += 1) {
    const low = bars[i]?.low;
    if (low !== undefined) {
      lowest = lowest === undefined ? low : Math.min(lowest, low);
    }
  }
  return lowest;
}

/** Highest high over the last `count` bars ending at `last`, never reaching before `from`. */
export function windowHigh(bars: readonly Candle[], from: number, last: number, count: number): number | undefined {
  let highest: number | undefined;
  for (let i = Math.max(from, last - count + 1); i <= last; i += 1) {
    const high = bars[i]?.high;
    if (high !== undefined) {
      highest = highest === undefined ? high : Math.max(highest, high);
    }
  }
  return highest;
}

/** Most recent strict fractal low (Bill Williams, `window` bars each side) confirmed by bar `last`. */
export function latestFractalLow(bars: readonly Candle[], last: number, window: number): number | undefined {
  for (let i = last - window; i >= window; i -= 1) {
    if (isPivotLow(bars, i, window, true)) {
      return bars[i]?.low;
    }
  }
  return undefined;
}

/**
 * The highest swing low accepted so far: the latest swing low confirmed before entry, then each later swing low
 * only if it is higher than the one held. A structure-progressive trail: it follows higher lows and ignores lower ones.
 */
export function acceptedSwingLow(bars: readonly Candle[], entryIndex: number, last: number, strength: number): number | undefined {
  let accepted: number | undefined;
  for (let i = strength; i + strength <= last; i += 1) {
    if (!isPivotLow(bars, i, strength, false)) {
      continue;
    }
    const low = bars[i]?.low ?? Number.NaN;
    const confirmedBeforeEntry = i + strength < entryIndex;
    if (confirmedBeforeEntry || accepted === undefined || low > accepted) {
      accepted = low;
    }
  }
  return accepted;
}

/**
 * The protected low: the swing low that stood when price last closed above an unbroken swing high (a bullish break
 * of structure). A close below it is a change of character. Swings are used only once confirmed.
 */
export function protectedLow(bars: readonly Candle[], last: number, strength: number): number | undefined {
  let lastSwingLow: number | undefined;
  let unbrokenHigh: number | undefined;
  let protectedLevel: number | undefined;
  for (let i = 0; i <= last; i += 1) {
    const pivot = i - strength;
    if (pivot >= strength) {
      lastSwingLow = isPivotLow(bars, pivot, strength, false) ? bars[pivot]?.low : lastSwingLow;
      unbrokenHigh = isPivotHigh(bars, pivot, strength, false) ? bars[pivot]?.high : unbrokenHigh;
    }
    const close = bars[i]?.close ?? Number.NaN;
    if (unbrokenHigh !== undefined && close > unbrokenHigh) {
      protectedLevel = lastSwingLow;
      unbrokenHigh = undefined;
    }
  }
  return protectedLevel;
}

export interface PsarParams {
  readonly af0: number;
  readonly step: number;
  readonly afMax: number;
}

/**
 * Parabolic SAR for a long held from bar `start`, as a stop only (it never reverses). Returns the SAR that applies
 * to the bar after `last`: each bar's SAR is built from closed bars only, clamped below the two prior lows.
 */
export function psarAfter(bars: readonly Candle[], start: number, last: number, initial: number, params: PsarParams): number | undefined {
  const first = bars[start];
  if (first === undefined || last < start) {
    return undefined;
  }
  let sar = initial;
  let extreme = first.high;
  let af = params.af0;
  for (let i = start + 1; i <= last + 1; i += 1) {
    sar += af * (extreme - sar);
    sar = Math.min(sar, bars[i - 1]?.low ?? sar, i - 2 >= start ? (bars[i - 2]?.low ?? sar) : sar);
    const high = bars[i]?.high;
    if (i <= last && high !== undefined && high > extreme) {
      extreme = high;
      af = Math.min(af + params.step, params.afMax);
    }
  }
  return sar;
}

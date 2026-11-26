import type { Candle, Direction } from '../domain/types.js';
import { efficiencyRatio, wilderAtr } from '../market/indicators.js';
import { isPivotHigh, isPivotLow } from '../market/stopLines.js';
import { istParts } from '../time/ist.js';

/** A fractal swing needs this many bars on each side; the swing is known only that many bars after it. */
const SWING_STRENGTH = 2;
const ATR_PERIOD = 14;
const REGIME_PERIOD = 12;
/** Kaufman efficiency at or above this over the last hour of 5-minute bars reads as a trending market. */
const TRENDING_EFFICIENCY = 0.3;
/** The day leans one way once price is this many ATRs from the day's open. */
const DAY_TREND_ATR = 1;
/** A structure shift this many bars old or newer still counts as fresh. */
const FRESH_SHIFT_BARS = 3;

export type Lean = Direction | 'NEUTRAL';

export interface StructureState {
  /** Direction of the last break of a swing: above the last swing high is bullish, below the last swing low bearish. */
  readonly trend: Lean;
  readonly lastSwingHigh: number | undefined;
  readonly lastSwingLow: number | undefined;
  /** The most recent break that changed the trend (market structure shift). */
  readonly shift: { readonly direction: Direction; readonly barTime: number; readonly barsAgo: number } | undefined;
}

export interface MarketContext {
  readonly dayTrend: Lean;
  readonly dayMoveAtr: number;
  readonly regime: 'TRENDING' | 'RANGING';
  readonly efficiency: number;
  readonly structure: StructureState;
}

export interface ContextVerdict {
  readonly ok: boolean;
  readonly score: number;
  readonly required: number;
  readonly reason: string;
}

/** Walks the bars once, confirming swings as they become known and recording each close that breaks one. */
export function marketStructure(bars: readonly Candle[]): StructureState {
  let trend: Lean = 'NEUTRAL';
  let lastSwingHigh: number | undefined;
  let lastSwingLow: number | undefined;
  let shiftIndex: number | undefined;
  for (let i = 0; i < bars.length; i += 1) {
    const pivot = i - SWING_STRENGTH;
    if (pivot >= SWING_STRENGTH) {
      lastSwingHigh = isPivotHigh(bars, pivot, SWING_STRENGTH, false) ? bars[pivot]?.high : lastSwingHigh;
      lastSwingLow = isPivotLow(bars, pivot, SWING_STRENGTH, false) ? bars[pivot]?.low : lastSwingLow;
    }
    const close = bars[i]?.close ?? Number.NaN;
    const broke: Lean =
      lastSwingHigh !== undefined && close > lastSwingHigh ? 'BULLISH' : lastSwingLow !== undefined && close < lastSwingLow ? 'BEARISH' : 'NEUTRAL';
    if (broke !== 'NEUTRAL' && broke !== trend) {
      shiftIndex = trend === 'NEUTRAL' ? undefined : i;
      trend = broke;
    }
  }
  const shiftBar = shiftIndex === undefined ? undefined : bars[shiftIndex];
  return {
    trend,
    lastSwingHigh,
    lastSwingLow,
    shift:
      shiftBar === undefined || shiftIndex === undefined || trend === 'NEUTRAL'
        ? undefined
        : { direction: trend, barTime: shiftBar.time, barsAgo: bars.length - 1 - shiftIndex },
  };
}

/** Day trend, regime and structure from closed bars; the last bar is the one just closed. */
export function marketContext(bars: readonly Candle[]): MarketContext {
  const last = bars[bars.length - 1];
  const atr = wilderAtr(bars, ATR_PERIOD).at(-1);
  const today = last === undefined ? undefined : istParts(last.time).date;
  const dayOpen = bars.find((bar) => istParts(bar.time).date === today)?.open;
  const dayMoveAtr = last !== undefined && dayOpen !== undefined && atr !== undefined && atr > 0 ? (last.close - dayOpen) / atr : 0;
  const efficiency = efficiencyRatio(bars, bars.length - 1, REGIME_PERIOD);
  return {
    dayTrend: dayMoveAtr >= DAY_TREND_ATR ? 'BULLISH' : dayMoveAtr <= -DAY_TREND_ATR ? 'BEARISH' : 'NEUTRAL',
    dayMoveAtr: Number(dayMoveAtr.toFixed(2)),
    regime: efficiency >= TRENDING_EFFICIENCY ? 'TRENDING' : 'RANGING',
    efficiency: Number(efficiency.toFixed(2)),
    structure: marketStructure(bars),
  };
}

function vote(lean: Lean, direction: Direction): number {
  return lean === 'NEUTRAL' ? 0 : lean === direction ? 1 : -1;
}

/**
 * Whether a long option on this side is supported. Day trend, structure and chain bias each vote +1 for, -1
 * against, and a fresh shift this way adds 1. A trending market needs a net vote of 1; a ranging one needs 2,
 * because breakouts in chop mostly fail. Buying against the day's trend needs one more: a single spike against
 * a trending day read as a fresh shift on 2026-10-23 and both such calls stopped out. Structure against the trade
 * is a veto, so the agent buys calls after a bullish shift, not into a falling structure.
 */
export function contextVerdict(context: MarketContext, direction: Direction, chainBias: Lean): ContextVerdict {
  const { structure } = context;
  const freshShift = structure.shift !== undefined && structure.shift.direction === direction && structure.shift.barsAgo <= FRESH_SHIFT_BARS;
  const score = vote(context.dayTrend, direction) + vote(structure.trend, direction) + vote(chainBias, direction) + (freshShift ? 1 : 0);
  const required = (context.regime === 'TRENDING' ? 1 : 2) + (vote(context.dayTrend, direction) < 0 ? 1 : 0);
  const detail = `day ${context.dayTrend} (${context.dayMoveAtr}x ATR), structure ${structure.trend}${freshShift ? ' after a fresh shift' : ''}, chain ${chainBias}, ${context.regime} (ER ${context.efficiency}): score ${score} of ${required} needed`;
  if (vote(structure.trend, direction) < 0) {
    return { ok: false, score, required, reason: `structure is ${structure.trend} against a ${direction} entry; ${detail}` };
  }
  return { ok: score >= required, score, required, reason: detail };
}

/** True when the newest bar shifted structure against a held position on this side. */
export function structureTurnedAgainst(structure: StructureState, held: Direction): boolean {
  return structure.shift !== undefined && structure.shift.barsAgo === 0 && structure.shift.direction !== held;
}

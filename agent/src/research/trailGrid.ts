import type { TrailSeries, TrailSpec } from '../exits/trail.js';

/**
 * The primary study family (docs/TRAILING_STOPS.md §3). Kept small on purpose: every entry is another test against
 * the same days and widens the multiple-testing correction. Regime-adaptive selection is added by the study itself.
 */
const BOTH: readonly TrailSeries[] = ['UNDERLYING', 'PREMIUM'];

function each<T>(values: readonly T[], build: (value: T) => TrailSpec[]): TrailSpec[] {
  return values.flatMap(build);
}

export const STUDY_GRID: readonly TrailSpec[] = [
  ...each([2, 3], (mult) => [0, 0.5].map((activationR): TrailSpec => ({ kind: 'ATR', period: 14, mult, activationR }))),
  ...each(BOTH, (series) =>
    each([series === 'UNDERLYING' ? 6 : 3, series === 'UNDERLYING' ? 10 : 6], (lookback) =>
      [2, 3].map((mult): TrailSpec => ({ kind: 'CHANDELIER', series, lookback, period: 14, mult })),
    ),
  ),
  ...each(BOTH, (series) => [2, 3].map((mult): TrailSpec => ({ kind: 'SUPERTREND', series, period: 10, mult }))),
  ...each(BOTH, (series) => [
    { kind: 'PSAR', series, af0: 0.02, step: 0.02, afMax: 0.2 },
    { kind: 'PSAR', series, af0: 0.01, step: 0.01, afMax: 0.1 },
  ]),
  ...each(BOTH, (series) => [
    { kind: 'MA_CROSS', series, ma: 'EMA', period: 9 },
    { kind: 'MA_CROSS', series, ma: 'EMA', period: 20 },
    { kind: 'MA_CROSS', series, ma: 'SMA', period: 20 },
    { kind: 'MA_CROSS', series, ma: 'ALMA', period: 9 },
    { kind: 'MA_CROSS', series, ma: 'ALMA', period: 21 },
    { kind: 'MA_CROSS', series, ma: 'HMA', period: 9 },
    { kind: 'MA_CROSS', series, ma: 'HMA', period: 21 },
  ]),
  ...each([2, 3], (strength) => [0, 0.25].map((bufferAtr): TrailSpec => ({ kind: 'SWING', strength, bufferAtr }))),
  { kind: 'FRACTAL', window: 2 },
  { kind: 'FRACTAL', window: 3 },
  { kind: 'CHOCH', strength: 2 },
  { kind: 'CHOCH', strength: 3 },
  ...each(BOTH, (series) => [3, 5, 10].map((bars): TrailSpec => ({ kind: 'DONCHIAN', series, bars }))),
  ...each([0.5, 1], (activationR) => [false, true].map((netBreakeven): TrailSpec => ({ kind: 'R_STAIRCASE', activationR, stepR: 1, netBreakeven }))),
  ...each([0.5, 1], (activationR) => [0.3, 0.5].map((giveback): TrailSpec => ({ kind: 'GIVEBACK', activationR, giveback }))),
  {
    kind: 'TIME_DECAY',
    schedule: [
      { uptoMinutes: 5, mult: 3 },
      { uptoMinutes: 10, mult: 2.5 },
      { uptoMinutes: 15, mult: 2 },
      { uptoMinutes: Infinity, mult: 1.5 },
    ],
  },
  {
    kind: 'TIME_DECAY',
    schedule: [
      { uptoMinutes: 5, mult: 2.5 },
      { uptoMinutes: 10, mult: 2 },
      { uptoMinutes: 15, mult: 1.5 },
      { uptoMinutes: Infinity, mult: 1 },
    ],
  },
  ...each([1.5, 2, 3], (mult) => [0, 0.5].map((activationR): TrailSpec => ({ kind: 'PREMIUM_ATR', period: 14, mult, activationR }))),
  ...each<TrailSpec>(
    [
      { kind: 'PREMIUM_ATR', period: 14, mult: 2, activationR: 0 },
      { kind: 'CHANDELIER', series: 'PREMIUM', lookback: 6, period: 14, mult: 2 },
    ],
    (premium) => [
      { kind: 'HYBRID', premium, underlying: { kind: 'CHOCH', strength: 2 } },
      { kind: 'HYBRID', premium, underlying: { kind: 'SUPERTREND', series: 'UNDERLYING', period: 10, mult: 3 } },
    ],
  ),
];

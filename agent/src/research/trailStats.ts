import { SeededRng } from './rng.js';
import { defaultBlockLength, percentile, resampleDays, type Interval } from './stats.js';
import type { StudyTrade } from './trailStudy.js';

/**
 * Paired statistics for the trailing-stop study (docs/TRAILING_STOPS.md §6). Every policy is replayed over the same
 * frozen entries, so the per-day difference against the baseline removes the entry noise that swamps an unpaired test.
 */

export interface PairedResult {
  /** Mean over days of the day's net P&L difference over the day's planned risk. */
  readonly meanDelta: number;
  readonly ci95: Interval;
  /** Share of day-block resamples whose mean difference was zero or below: a one-sided p for "beats the baseline". */
  readonly pNonPositive: number;
}

/** One value per replayed day, in date order: Σ(candidate − baseline net) / Σ risk. Days without trades give 0. */
export function dailyDeltas(dates: readonly string[], baseline: readonly StudyTrade[], candidate: readonly StudyTrade[]): number[] {
  if (baseline.length !== candidate.length) {
    throw new Error(`paired policies need the same entries: baseline has ${baseline.length}, candidate ${candidate.length}`);
  }
  const byDate = new Map(dates.map((date) => [date, { delta: 0, risk: 0 }]));
  baseline.forEach((base, i) => {
    const other = candidate[i];
    const day = byDate.get(base.date);
    if (other === undefined || day === undefined || other.entryTime !== base.entryTime) {
      throw new Error(`entry ${i} on ${base.date} is not paired`);
    }
    day.delta += other.netPnlInr - base.netPnlInr;
    day.risk += base.riskInr;
  });
  return dates.map((date) => {
    const day = byDate.get(date);
    return day === undefined || day.risk === 0 ? 0 : day.delta / day.risk;
  });
}

function mean(values: readonly number[]): number {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

/** Circular day-block bootstrap of the mean daily difference. */
export function pairedBootstrap(deltas: readonly number[], options: { iterations: number; seed: number }): PairedResult {
  const rng = new SeededRng(options.seed);
  const blockLength = defaultBlockLength(deltas.length);
  const means: number[] = [];
  for (let i = 0; i < options.iterations; i += 1) {
    means.push(mean(resampleDays(deltas, deltas.length, blockLength, rng)));
  }
  means.sort((a, b) => a - b);
  return {
    meanDelta: mean(deltas),
    ci95: { low: percentile(means, 0.025), high: percentile(means, 0.975) },
    pNonPositive: means.filter((value) => value <= 0).length / Math.max(1, means.length),
  };
}

/** Holm–Bonferroni step-down adjustment. Returns adjusted p-values in the input order, capped at 1. */
export function holm(pValues: readonly number[]): number[] {
  const order = pValues.map((p, index) => ({ p, index })).sort((a, b) => a.p - b.p);
  const adjusted = new Array<number>(pValues.length).fill(1);
  let running = 0;
  order.forEach(({ p, index }, rank) => {
    running = Math.max(running, Math.min(1, (pValues.length - rank) * p));
    adjusted[index] = running;
  });
  return adjusted;
}

/**
 * White's reality check: is the best policy's mean difference larger than the best that a search over these policies
 * would produce by chance? Each resample draws the same days for every policy, so their correlation is kept.
 */
export function realityCheck(deltasByPolicy: readonly (readonly number[])[], options: { iterations: number; seed: number }): number {
  const days = deltasByPolicy[0]?.length ?? 0;
  if (days === 0) {
    return 1;
  }
  const observedMeans = deltasByPolicy.map(mean);
  const observedMax = Math.max(...observedMeans);
  const rng = new SeededRng(options.seed);
  const indices = Array.from({ length: days }, (_, i) => i);
  const blockLength = defaultBlockLength(days);
  let atLeast = 0;
  for (let i = 0; i < options.iterations; i += 1) {
    const draw = resampleDays(indices, days, blockLength, rng);
    const centredMax = Math.max(...deltasByPolicy.map((deltas, m) => mean(draw.map((day) => deltas[day] ?? 0)) - (observedMeans[m] ?? 0)));
    atLeast += centredMax >= observedMax ? 1 : 0;
  }
  return atLeast / options.iterations;
}

/** Net captured over opportunity, as a ratio of sums. Undefined when no trade had any opportunity. */
export function capture(trades: readonly StudyTrade[]): number | undefined {
  const opportunity = trades.reduce((sum, trade) => sum + trade.opportunityInr, 0);
  return opportunity > 0 ? trades.reduce((sum, trade) => sum + trade.netPnlInr, 0) / opportunity : undefined;
}

export interface Fold {
  readonly train: readonly string[];
  readonly test: string;
}

/** Rolling monthly folds over `YYYY-MM` months: `trainMonths` to train, the next month to test, step one month. */
export function walkForwardFolds(months: readonly string[], trainMonths: number): Fold[] {
  const sorted = [...new Set(months)].sort();
  const folds: Fold[] = [];
  for (let start = 0; start + trainMonths < sorted.length; start += 1) {
    folds.push({ train: sorted.slice(start, start + trainMonths), test: sorted[start + trainMonths] as string });
  }
  return folds;
}

export interface PolicyTrades {
  readonly id: string;
  /** One trade per frozen entry, in entry order. */
  readonly trades: readonly StudyTrade[];
}

export interface WalkForwardResult {
  readonly folds: readonly { readonly test: string; readonly selected: string }[];
  /** Out-of-sample trades of whichever policy each fold selected, with the baseline's for the same entries. */
  readonly selected: readonly StudyTrade[];
  readonly baseline: readonly StudyTrade[];
  readonly dates: readonly string[];
}

const monthOf = (date: string): string => date.slice(0, 7);

function pick<T>(items: readonly T[], keep: (index: number) => boolean): T[] {
  return items.filter((_, index) => keep(index));
}

/** The policy with the best capture on these entries among those whose mean daily difference is not negative. */
function bestPolicy(policies: readonly PolicyTrades[], baseline: readonly StudyTrade[], dates: readonly string[], keep: (index: number) => boolean): PolicyTrades | undefined {
  let best: { policy: PolicyTrades; score: number } | undefined;
  const base = pick(baseline, keep);
  for (const policy of policies) {
    const trades = pick(policy.trades, keep);
    const score = capture(trades);
    const notWorse = mean(dailyDeltas(dates, base, trades)) >= 0;
    if (score !== undefined && notWorse && (best === undefined || score > best.score)) {
      best = { policy, score };
    }
  }
  return best?.policy;
}

interface WalkForwardInput {
  readonly dates: readonly string[];
  readonly baseline: readonly StudyTrade[];
  readonly policies: readonly PolicyTrades[];
  readonly trainMonths: number;
  /** Per entry, its context cell. Present: choose a policy per cell (regime-adaptive). */
  readonly cells?: readonly string[];
  readonly minCellTrades?: number;
}

/** Selects on the fold's training months and returns the chosen policy's trades for its test month. */
function runFold(fold: Fold, input: WalkForwardInput): { label: string; chosen: StudyTrade[]; base: StudyTrade[] } {
  const { baseline, policies, cells } = input;
  const inTrain = (i: number): boolean => fold.train.includes(monthOf(baseline[i]?.date ?? ''));
  const trainDates = input.dates.filter((date) => fold.train.includes(monthOf(date)));
  const overall = bestPolicy(policies, baseline, trainDates, inTrain) ?? policies[0];
  const perCell = new Map<string, PolicyTrades | undefined>();
  const policyFor = (cell: string): PolicyTrades | undefined => {
    if (!perCell.has(cell)) {
      const inCell = (k: number): boolean => inTrain(k) && cells?.[k] === cell;
      const enough = baseline.filter((_, k) => inCell(k)).length >= (input.minCellTrades ?? 30);
      perCell.set(cell, enough ? bestPolicy(policies, baseline, trainDates, inCell) : undefined);
    }
    return perCell.get(cell);
  };
  const chosen: StudyTrade[] = [];
  const base: StudyTrade[] = [];
  baseline.forEach((trade, i) => {
    const cell = cells?.[i];
    const policy = (cell === undefined ? undefined : policyFor(cell)) ?? overall;
    if (monthOf(trade.date) === fold.test && policy !== undefined) {
      chosen.push(policy.trades[i] as StudyTrade);
      base.push(trade);
    }
  });
  return { label: cells === undefined ? (overall?.id ?? 'none') : `${[...perCell.values()].filter(Boolean).length}/${perCell.size} cells own policy`, chosen, base };
}

/**
 * Rolling monthly walk-forward. Each fold selects on its training months only and is scored on the next month, so
 * the concatenated test months are the honest estimate of what the selection procedure would have earned.
 */
export function walkForward(input: WalkForwardInput): WalkForwardResult {
  const folds = walkForwardFolds(input.dates.map(monthOf), input.trainMonths);
  const runs = folds.map((fold) => ({ test: fold.test, ...runFold(fold, input) }));
  const testMonths = new Set(folds.map((fold) => fold.test));
  return {
    folds: runs.map((run) => ({ test: run.test, selected: run.label })),
    selected: runs.flatMap((run) => run.chosen),
    baseline: runs.flatMap((run) => run.base),
    dates: input.dates.filter((date) => testMonths.has(monthOf(date))),
  };
}

/**
 * Day-paired difference for two replays whose trades differ (the coupled mode): per day, the net difference over the
 * larger of the two days' planned risk. Days with no risk on either side give 0.
 */
export function dayNetDeltas(dates: readonly string[], baseline: readonly { date: string; netPnlInr: number; riskInr: number }[], candidate: readonly { date: string; netPnlInr: number; riskInr: number }[]): number[] {
  const sum = (trades: typeof baseline, date: string, key: 'netPnlInr' | 'riskInr'): number =>
    trades.filter((trade) => trade.date === date).reduce((total, trade) => total + trade[key], 0);
  return dates.map((date) => {
    const risk = Math.max(sum(baseline, date, 'riskInr'), sum(candidate, date, 'riskInr'));
    return risk === 0 ? 0 : (sum(candidate, date, 'netPnlInr') - sum(baseline, date, 'netPnlInr')) / risk;
  });
}

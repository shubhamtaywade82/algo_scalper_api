import { SeededRng } from './rng.js';

/** What the statistics need from a trade. Data-gap trades are removed before this point. */
export interface TradeSample {
  readonly date: string;
  readonly netPnlInr: number;
  readonly r: number;
  readonly exitReason: string;
}

export interface Interval {
  readonly low: number;
  readonly high: number;
}

export interface Percentiles {
  readonly p5: number;
  readonly p50: number;
  readonly p95: number;
}

export interface SampleSummary {
  readonly trades: number;
  readonly days: number;
  readonly wins: number;
  readonly winRate: number;
  readonly winRateCi95: Interval;
  /** Win rate that would make expectancy zero at the observed average win and loss sizes. */
  readonly breakevenWinRate: number | undefined;
  readonly meanR: number;
  readonly meanNetInr: number;
  readonly totalNetInr: number;
  readonly profitFactor: number | undefined;
  readonly maxDrawdownInr: number;
  readonly targetFirst: { readonly rate: number; readonly ci95: Interval };
  readonly stopFirst: { readonly rate: number; readonly ci95: Interval };
  /** Closed by time, EOD, structure or daily loss: neither bracket leg decided it. */
  readonly unresolved: { readonly rate: number; readonly ci95: Interval };
}

const Z95 = 1.959964;

function round(value: number, places = 4): number {
  return Number(value.toFixed(places));
}

/** Wilson score interval: honest at small n and near 0 or 1, where the normal approximation is not. */
export function wilsonInterval(successes: number, n: number, z = Z95): Interval {
  if (n === 0) {
    return { low: 0, high: 1 };
  }
  const p = successes / n;
  const denominator = 1 + (z * z) / n;
  const centre = p + (z * z) / (2 * n);
  const margin = z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n));
  return { low: round(Math.max(0, (centre - margin) / denominator)), high: round(Math.min(1, (centre + margin) / denominator)) };
}

/** Linear-interpolated percentile of an ascending array. */
export function percentile(sorted: readonly number[], q: number): number {
  if (sorted.length === 0) {
    return Number.NaN;
  }
  const position = (sorted.length - 1) * q;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  const a = sorted[lower] as number;
  const b = sorted[upper] as number;
  return a + (b - a) * (position - lower);
}

function percentiles(values: number[]): Percentiles {
  const sorted = [...values].sort((a, b) => a - b);
  return { p5: round(percentile(sorted, 0.05), 2), p50: round(percentile(sorted, 0.5), 2), p95: round(percentile(sorted, 0.95), 2) };
}

/** Peak-to-trough fall of the cumulative P&L, as a positive number. */
export function maxDrawdown(pnls: readonly number[]): number {
  let equity = 0;
  let peak = 0;
  let worst = 0;
  for (const pnl of pnls) {
    equity += pnl;
    peak = Math.max(peak, equity);
    worst = Math.max(worst, peak - equity);
  }
  return round(worst, 2);
}

export function summarize(trades: readonly TradeSample[], days: number): SampleSummary {
  const n = trades.length;
  const wins = trades.filter((trade) => trade.netPnlInr > 0);
  const losses = trades.filter((trade) => trade.netPnlInr <= 0);
  const grossWin = wins.reduce((total, trade) => total + trade.netPnlInr, 0);
  const grossLoss = -losses.reduce((total, trade) => total + trade.netPnlInr, 0);
  const avgWinR = wins.length === 0 ? undefined : wins.reduce((total, trade) => total + trade.r, 0) / wins.length;
  const avgLossR = losses.length === 0 ? undefined : -losses.reduce((total, trade) => total + trade.r, 0) / losses.length;
  const count = (reason: string): number => trades.filter((trade) => trade.exitReason === reason).length;
  const rate = (k: number): { rate: number; ci95: Interval } => ({ rate: n === 0 ? 0 : round(k / n), ci95: wilsonInterval(k, n) });
  const targets = count('TARGET');
  const stops = count('STOP_LOSS');
  const totalNetInr = trades.reduce((total, trade) => total + trade.netPnlInr, 0);
  return {
    trades: n,
    days,
    wins: wins.length,
    winRate: n === 0 ? 0 : round(wins.length / n),
    winRateCi95: wilsonInterval(wins.length, n),
    breakevenWinRate: avgWinR === undefined || avgLossR === undefined || avgWinR + avgLossR <= 0 ? undefined : round(avgLossR / (avgWinR + avgLossR)),
    meanR: n === 0 ? 0 : round(trades.reduce((total, trade) => total + trade.r, 0) / n),
    meanNetInr: n === 0 ? 0 : round(totalNetInr / n, 2),
    totalNetInr: round(totalNetInr, 2),
    profitFactor: grossLoss === 0 ? undefined : round(grossWin / grossLoss, 3),
    maxDrawdownInr: maxDrawdown(trades.map((trade) => trade.netPnlInr)),
    targetFirst: rate(targets),
    stopFirst: rate(stops),
    unresolved: rate(n - targets - stops),
  };
}

/** Every replayed day with its trades in order, including days with none: trade frequency is part of the result. */
export interface DayOutcome {
  readonly date: string;
  readonly trades: readonly TradeSample[];
}

export function groupByDay(dates: readonly string[], trades: readonly TradeSample[]): DayOutcome[] {
  const byDate = new Map<string, TradeSample[]>(dates.map((date) => [date, []]));
  for (const trade of trades) {
    const day = byDate.get(trade.date);
    if (day === undefined) {
      throw new Error(`trade on ${trade.date} is outside the replayed days`);
    }
    day.push(trade);
  }
  return dates.map((date) => ({ date, trades: byDate.get(date) ?? [] }));
}

/** Politis–White style default: block length grows as n^(1/3). */
/**
 * Blocks for the holdout bootstrap are at least this many sessions, so dependence within a trading week survives the
 * resample. The cube-root rule alone gives 3 sessions on a 30-session holdout, which is too short.
 */
export const MIN_HOLDOUT_BLOCK_DAYS = 5;

export function holdoutBlockLength(days: number): number {
  return Math.max(MIN_HOLDOUT_BLOCK_DAYS, defaultBlockLength(days));
}

/** The largest share of all positive net R that one session supplies. Undefined when no session made money. */
export function bestSessionShare(days: readonly DayOutcome[]): number | undefined {
  const totals = days.map((day) => day.trades.reduce((sum, trade) => sum + trade.r, 0));
  const positive = totals.filter((total) => total > 0);
  const positiveSum = positive.reduce((sum, total) => sum + total, 0);
  if (positiveSum <= 0) {
    return undefined;
  }
  return Math.max(...positive) / positiveSum;
}

/** Significance level of the derived profit-share cap: a holdout with no special session exceeds it this often. */
export const DOMINANCE_ALPHA = 0.05;
export const DOMINANCE_SIMULATIONS = 10_000;

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? (sorted[middle] as number) : ((sorted[middle - 1] as number) + (sorted[middle] as number)) / 2;
}

function standardNormal(rng: SeededRng): number {
  const u1 = Math.max(rng.next(), Number.MIN_VALUE);
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * rng.next());
}

/**
 * The derived cap for `winningSessions` winning sessions with the given median and spread. It is the (1 − alpha) quantile of
 * the largest session's share, when the winning sessions are exchangeable draws from a normal with that median and spread,
 * truncated to positive. Deterministic for a seed. With no spread, every winner is equal, so the cap is the fair share 1/W.
 */
export function simulatedDominanceCap(winningSessions: number, median: number, spread: number, seed: number): number | undefined {
  if (winningSessions < 2 || !(median > 0)) {
    return undefined;
  }
  if (spread === 0) {
    return 1 / winningSessions;
  }
  const rng = new SeededRng(seed);
  const shares: number[] = [];
  for (let simulation = 0; simulation < DOMINANCE_SIMULATIONS; simulation += 1) {
    let sum = 0;
    let largest = 0;
    for (let session = 0; session < winningSessions; session += 1) {
      let draw = Number.NaN;
      while (!(draw > 0)) {
        draw = median + spread * standardNormal(rng);
      }
      sum += draw;
      largest = Math.max(largest, draw);
    }
    shares.push(largest / sum);
  }
  shares.sort((a, b) => a - b);
  return shares[Math.min(shares.length - 1, Math.ceil((1 - DOMINANCE_ALPHA) * shares.length) - 1)];
}

/**
 * The cap for a holdout's own winning sessions. Its location and spread are the median and the scaled median absolute
 * deviation (1.4826 × MAD) of those sessions. The MAD is used, not the standard deviation, because a standard deviation
 * would be inflated by the very outlier the cap exists to catch.
 */
export function dominanceCap(positiveTotals: readonly number[], seed: number): number | undefined {
  if (positiveTotals.length < 2) {
    return undefined;
  }
  const centre = median(positiveTotals);
  const spread = 1.4826 * median(positiveTotals.map((total) => Math.abs(total - centre)));
  return simulatedDominanceCap(positiveTotals.length, centre, spread, seed);
}

export interface DominanceTest {
  readonly share: number | undefined;
  readonly cap: number | undefined;
  readonly winningSessions: number;
  /** Passes only when both the share and the cap are defined and the share does not exceed the cap. */
  readonly passes: boolean;
}

/** The profit-share test for a holdout: does its largest winning session stay within the cap derived from its own winners? */
export function dominanceTest(days: readonly DayOutcome[], seed: number): DominanceTest {
  const totals = days.map((day) => day.trades.reduce((sum, trade) => sum + trade.r, 0));
  const positive = totals.filter((total) => total > 0);
  const share = bestSessionShare(days);
  const cap = dominanceCap(positive, seed);
  // The tolerance absorbs rounding: identical winners give a share exactly equal to the fair share.
  const passes = share !== undefined && cap !== undefined && share <= cap + 1e-9;
  return { share, cap, winningSessions: positive.length, passes };
}

/**
 * Mean net R of the holdout with its single most profitable session removed. A result that needs one session to stay
 * positive is not robust. Undefined when nothing is left to average.
 */
export function meanWithoutBestSession(days: readonly DayOutcome[]): number | undefined {
  if (days.length === 0) {
    return undefined;
  }
  const totals = days.map((day) => ({ day, total: day.trades.reduce((sum, trade) => sum + trade.r, 0) }));
  const best = totals.reduce((top, next) => (next.total > top.total ? next : top));
  const rest = days.filter((day) => day !== best.day).flatMap((day) => day.trades);
  if (rest.length === 0) {
    return undefined;
  }
  return rest.reduce((sum, trade) => sum + trade.r, 0) / rest.length;
}

export function defaultBlockLength(days: number): number {
  return Math.max(1, Math.round(Math.cbrt(days)));
}

/**
 * Circular moving-block resample of whole days. Trades inside a day stay together and neighbouring days stay
 * neighbours within a block, so intraday dependence and short regime runs survive the resample, which an iid
 * draw of single trades would destroy.
 */
export function resampleDays<T>(days: readonly T[], length: number, blockLength: number, rng: SeededRng): T[] {
  const out: T[] = [];
  while (out.length < length) {
    const start = rng.int(days.length);
    for (let k = 0; k < blockLength && out.length < length; k += 1) {
      out.push(days[(start + k) % days.length] as T);
    }
  }
  return out;
}

export interface BootstrapResult {
  readonly iterations: number;
  readonly seed: number;
  readonly blockLength: number;
  /** 95% percentile interval of mean net R per trade. */
  readonly meanRCi95: Interval;
  /** Share of resamples whose mean net R was zero or below. */
  readonly probMeanRNonPositive: number;
  /** Resamples that drew no trade at all; excluded from the interval. */
  readonly emptyResamples: number;
}

/**
 * Question answered: given only these days, how sure can we be that the mean trade is positive? Sampling
 * uncertainty of the historical mean, not a forecast.
 */
export function bootstrapMeanR(days: readonly DayOutcome[], options: { iterations: number; seed: number; blockLength?: number }): BootstrapResult {
  if (days.length === 0) {
    throw new Error('bootstrap needs at least one day');
  }
  const blockLength = options.blockLength ?? defaultBlockLength(days.length);
  const rng = new SeededRng(options.seed);
  const means: number[] = [];
  let empty = 0;
  for (let i = 0; i < options.iterations; i += 1) {
    let total = 0;
    let count = 0;
    for (const day of resampleDays(days, days.length, blockLength, rng)) {
      for (const trade of day.trades) {
        total += trade.r;
        count += 1;
      }
    }
    if (count === 0) {
      empty += 1;
      continue;
    }
    means.push(total / count);
  }
  const sorted = means.sort((a, b) => a - b);
  return {
    iterations: options.iterations,
    seed: options.seed,
    blockLength,
    meanRCi95: { low: round(percentile(sorted, 0.025)), high: round(percentile(sorted, 0.975)) },
    probMeanRNonPositive: sorted.length === 0 ? 1 : round(sorted.filter((mean) => mean <= 0).length / sorted.length),
    emptyResamples: empty,
  };
}

export interface PathSimulation {
  readonly paths: number;
  readonly seed: number;
  readonly blockLength: number;
  readonly horizonDays: number;
  readonly netInr: Percentiles;
  readonly maxDrawdownInr: Percentiles;
  readonly probLoss: number;
  /** Share of paths whose drawdown reached the alarm level. */
  readonly probDrawdownAtLeast: { readonly thresholdInr: number; readonly probability: number };
}

/**
 * Question answered: if the next `horizonDays` look like a re-ordering of these days, how wide is the spread of
 * outcomes and how deep can the drawdown get? Monte Carlo over the empirical day distribution; no parametric
 * return model is assumed.
 */
export function simulatePaths(
  days: readonly DayOutcome[],
  options: { paths: number; seed: number; horizonDays: number; drawdownAlarmInr: number; blockLength?: number },
): PathSimulation {
  if (days.length === 0) {
    throw new Error('path simulation needs at least one day');
  }
  const blockLength = options.blockLength ?? defaultBlockLength(days.length);
  const rng = new SeededRng(options.seed);
  const totals: number[] = [];
  const drawdowns: number[] = [];
  for (let i = 0; i < options.paths; i += 1) {
    const pnls = resampleDays(days, options.horizonDays, blockLength, rng).flatMap((day) => day.trades.map((trade) => trade.netPnlInr));
    totals.push(pnls.reduce((total, pnl) => total + pnl, 0));
    drawdowns.push(maxDrawdown(pnls));
  }
  return {
    paths: options.paths,
    seed: options.seed,
    blockLength,
    horizonDays: options.horizonDays,
    netInr: percentiles(totals),
    maxDrawdownInr: percentiles(drawdowns),
    probLoss: round(totals.filter((total) => total < 0).length / options.paths),
    probDrawdownAtLeast: {
      thresholdInr: options.drawdownAlarmInr,
      probability: round(drawdowns.filter((drawdown) => drawdown >= options.drawdownAlarmInr).length / options.paths),
    },
  };
}

/** Chronological split: the first `fraction` of days, then the rest. Never shuffled. */
export function chronologicalSplit<T extends { readonly date: string }>(days: readonly T[], fraction: number): { inSample: T[]; outOfSample: T[] } {
  if (!(fraction > 0 && fraction < 1)) {
    throw new RangeError(`split fraction must be in (0, 1), got ${fraction}`);
  }
  const cut = Math.round(days.length * fraction);
  return { inSample: days.slice(0, cut), outOfSample: days.slice(cut) };
}

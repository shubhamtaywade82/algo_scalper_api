import type { Candle } from '../domain/types.js';
import { istParts } from '../time/ist.js';
import type { ReplayResult, ReplayTrade } from './replay.js';
import { bootstrapMeanR, chronologicalSplit, dominanceTest, groupByDay, holdoutBlockLength, meanWithoutBestSession, summarize, type Interval, type TradeSample } from './stats.js';

/** Extra per-day tags joined by date, such as the VIX tercile. */
export type DayTags = ReadonlyMap<string, Readonly<Record<string, string>>>;

export interface CellOptions {
  readonly iterations: number;
  readonly seed: number;
  readonly minTrades: number;
  readonly splitFraction: number;
  /**
   * Variants evaluated before this run across the whole research program: logged runs on any dataset, plus seeded
   * floors (`ledger.ts`). Each was another draw from the same search, so each multiplies the test count.
   */
  readonly priorRuns: number;
  /** Independent sessions the holdout must span before a cell can be EDGE_SUPPORTED. */
  readonly minHoldoutDays: number;
  /** Adds the entry's implied-volatility bucket as a dimension. Off by default, so existing cell runs are unchanged. */
  readonly includeIv?: boolean;
}

export interface Cell {
  /** `strategy | dimension=value`. */
  readonly key: string;
  readonly trades: number;
  readonly meanR: number;
  readonly profitFactor: number | undefined;
  readonly meanRCi95: Interval | undefined;
  readonly probMeanRNonPositive: number;
  readonly outOfSampleMeanR: number;
  readonly verdict: 'INSUFFICIENT_EVIDENCE' | 'NO_TRADE' | 'EDGE_SUPPORTED';
}

export interface CellReport {
  readonly cells: readonly Cell[];
  /** Cells in this report times runs on this dataset: the Bonferroni divisor. */
  readonly testsCounted: number;
  /** One-sided bar on P(mean net R ≤ 0) each cell must clear. */
  readonly threshold: number;
}

/** One-sided, matching the lower bound of the 95% interval the whole-sample verdict uses. */
const FAMILY_ALPHA = 0.025;

/**
 * Cost stress for cells, with the same rule as the Time Machine verdict: a cell stays EDGE_SUPPORTED only if the same
 * cell is EDGE_SUPPORTED under every stressed cost model. Otherwise it is NO_TRADE. It never upgrades a cell.
 */
export function applyCostStressToCells(base: CellReport, stresses: readonly { readonly label: string; readonly report: CellReport }[]): CellReport {
  const cells = base.cells.map((cell) => {
    if (cell.verdict !== 'EDGE_SUPPORTED') {
      return cell;
    }
    const holds = stresses.every((stress) => stress.report.cells.find((other) => other.key === cell.key)?.verdict === 'EDGE_SUPPORTED');
    return holds ? cell : { ...cell, verdict: 'NO_TRADE' as const };
  });
  return { ...base, cells };
}

function cellValues(trade: ReplayTrade, dayTags: DayTags, includeIv: boolean): Record<string, string> {
  const { regime, trendAlignment, timeBucket, expiryDay, volatility, structureAlignment, expiryBucket } = trade.context;
  // chainBias is not a dimension: it is UNKNOWN on every trade, so a cell on it would only add to the divisor.
  return {
    regime,
    trendAlignment,
    timeBucket,
    expiryDay: String(expiryDay),
    volatility,
    structureAlignment,
    expiryBucket,
    ...(includeIv ? { ivBucket: trade.context.ivBucket } : {}),
    ...dayTags.get(trade.date),
  };
}

function groupCells(trades: readonly ReplayTrade[], dayTags: DayTags, includeIv: boolean): Map<string, ReplayTrade[]> {
  const groups = new Map<string, ReplayTrade[]>();
  for (const trade of trades) {
    for (const [dimension, value] of Object.entries(cellValues(trade, dayTags, includeIv))) {
      const key = `${trade.strategy} | ${dimension}=${value}`;
      groups.set(key, [...(groups.get(key) ?? []), trade]);
    }
  }
  return groups;
}

function judgeCell(key: string, trades: readonly ReplayTrade[], dates: readonly string[], options: CellOptions, threshold: number): Cell {
  const samples: TradeSample[] = trades.map((trade) => ({ date: trade.date, netPnlInr: trade.netPnlInr, r: trade.r, exitReason: trade.exitReason }));
  const days = groupByDay(dates, samples);
  const summary = summarize(samples, days.length);
  // Judged on the holdout (the later days) only. The whole-cell figures are reported for context and never decide.
  const holdout = chronologicalSplit(days, options.splitFraction).outOfSample;
  const holdoutTrades = holdout.flatMap((day) => day.trades);
  const outOfSampleMeanR = summarize(holdoutTrades, 0).meanR;
  const bootstrap =
    holdout.length > 0 && holdoutTrades.length > 0
      ? bootstrapMeanR(holdout, { iterations: options.iterations, seed: options.seed, blockLength: holdoutBlockLength(holdout.length) })
      : undefined;
  let verdict: Cell['verdict'] = 'NO_TRADE';
  if (holdoutTrades.length < options.minTrades || holdout.length < options.minHoldoutDays || bootstrap === undefined) {
    verdict = 'INSUFFICIENT_EVIDENCE';
  } else if (bootstrap.probMeanRNonPositive < threshold && outOfSampleMeanR > 0) {
    // Robust only if the holdout mean stays positive without its single best session (OTA-308 eligibility).
    const robust = (meanWithoutBestSession(holdout) ?? 0) > 0 && dominanceTest(holdout, options.seed).passes;
    verdict = robust ? 'EDGE_SUPPORTED' : 'NO_TRADE';
  }
  return {
    key,
    trades: trades.length,
    meanR: summary.meanR,
    profitFactor: summary.profitFactor,
    meanRCi95: bootstrap?.meanRCi95,
    probMeanRNonPositive: bootstrap?.probMeanRNonPositive ?? 1,
    outOfSampleMeanR,
    verdict,
  };
}

/**
 * Each strategy's priced trades split by one context dimension at a time. A cell is EDGE_SUPPORTED only when
 * P(mean net R ≤ 0) clears the Bonferroni-corrected bar for every cell and run tested, and its later days hold up.
 */
export function contextCells(result: Pick<ReplayResult, 'trades' | 'dates'>, dayTags: DayTags, options: CellOptions): CellReport {
  const priced = result.trades.filter((trade) => trade.exitReason !== 'DATA_GAP');
  const groups = [...groupCells(priced, dayTags, options.includeIv === true)].sort(([a], [b]) => a.localeCompare(b));
  const testsCounted = Math.max(1, groups.length) * (options.priorRuns + 1);
  const threshold = FAMILY_ALPHA / testsCounted;
  const cells = groups.map(([key, trades]) => judgeCell(key, trades, result.dates, options, threshold));
  return { cells, testsCounted, threshold };
}

/** Earlier sessions of opening VIX a day is ranked against, and the least history that gives it a tag. Fixed before use. */
export const VIX_LOOKBACK_SESSIONS = 252;
export const VIX_MIN_HISTORY = 60;

/**
 * LOW / MID / HIGH by each date's opening VIX (its first bar's open), ranked against the opening VIX of the earlier
 * sessions. Only earlier sessions are used, so the tag is known before the day's entries. A date with fewer than
 * VIX_MIN_HISTORY earlier sessions, or with no VIX, gets no tag. Before 2026-11-13 this ranked every date against all the
 * dates in the dataset, which used later days; cell reports printed before that change are not valid evidence.
 */
export function vixTerciles(vixBars: readonly Candle[], dates: readonly string[]): Map<string, { vix: string }> {
  const opens = new Map<string, number>();
  for (const bar of [...vixBars].sort((a, b) => a.time - b.time)) {
    const date = istParts(bar.time).date;
    if (!opens.has(date)) {
      opens.set(date, bar.open);
    }
  }
  const sessions = [...opens].sort(([a], [b]) => a.localeCompare(b));
  const tags = new Map<string, { vix: string }>();
  for (const date of dates) {
    const today = opens.get(date);
    if (today === undefined) {
      continue;
    }
    const history = sessions
      .filter(([session]) => session < date)
      .slice(-VIX_LOOKBACK_SESSIONS)
      .map(([, open]) => open);
    const label = trailingTercile(history, today);
    if (label !== undefined) {
      tags.set(date, { vix: label });
    }
  }
  return tags;
}

/** Mid-rank tercile of `current` within `history`, or undefined without VIX_MIN_HISTORY observations. */
function trailingTercile(history: readonly number[], current: number): 'LOW' | 'MID' | 'HIGH' | undefined {
  if (history.length < VIX_MIN_HISTORY) {
    return undefined;
  }
  const below = history.filter((value) => value < current).length;
  const tied = history.filter((value) => value === current).length;
  const rank = (below + tied / 2) / history.length;
  if (rank < 1 / 3) {
    return 'LOW';
  }
  return rank >= 2 / 3 ? 'HIGH' : 'MID';
}

export function formatCells(report: CellReport): string {
  const lines = [
    `Context cells: ${report.cells.length} cells, ${report.testsCounted} tests counted; a cell needs P(mean net R ≤ 0) < ${report.threshold.toExponential(2)}`,
    'cell | trades | mean net R | 95% CI | P(≤0) | out-of-sample R | PF | verdict',
  ];
  for (const cell of report.cells) {
    const ci = cell.meanRCi95 === undefined ? 'n/a' : `${cell.meanRCi95.low} to ${cell.meanRCi95.high}`;
    lines.push(`${cell.key} | ${cell.trades} | ${cell.meanR} | ${ci} | ${cell.probMeanRNonPositive} | ${cell.outOfSampleMeanR} | ${cell.profitFactor ?? 'n/a'} | ${cell.verdict}`);
  }
  return lines.join('\n');
}

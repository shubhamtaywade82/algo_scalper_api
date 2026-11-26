import type { Candle } from '../domain/types.js';
import { legBars, type ResearchDataset, type ResearchSession } from './dataset.js';
import type { ReplayTrade } from './replay.js';
import type { StudyEntry } from './trailStudy.js';

/** Freezes the baseline replay's priced trades as study entries, each with the bars its exit path needs. */
export function freezeEntries(dataset: ResearchDataset, baseline: readonly ReplayTrade[], warmupSessions: number): StudyEntry[] {
  const indexByDate = new Map(dataset.sessions.map((session, index) => [session.date, index]));
  return baseline
    .filter((trade) => trade.exitReason !== 'DATA_GAP')
    .map((trade) => {
      const index = indexByDate.get(trade.date);
      const session = index === undefined ? undefined : dataset.sessions[index];
      if (index === undefined || session === undefined) {
        throw new Error(`trade on ${trade.date} has no session in the dataset`);
      }
      const warmup = dataset.sessions.slice(Math.max(0, index - warmupSessions), index).flatMap((day) => day.spot);
      return { trade, session, warmup, optionSegment: dataset.optionSegment, underlying: dataset.underlying };
    });
}

/** 1-minute bars inside each 5-minute bar, keyed by the 5-minute bar's open time (docs/TRAILING_STOPS.md §5.4). */
export interface FineBars {
  readonly premium: ReadonlyMap<number, readonly Candle[]>;
  readonly spot: ReadonlyMap<number, readonly Candle[]>;
}

function bucket(bars: readonly Candle[], barMs: number): Map<number, Candle[]> {
  const out = new Map<number, Candle[]>();
  for (const bar of bars) {
    const start = bar.time - (bar.time % barMs);
    const group = out.get(start) ?? [];
    group.push(bar);
    out.set(start, group);
  }
  return out;
}

/**
 * The entry's held strike and the spot on the 1-minute session of the same day, grouped into the 5-minute bars.
 * Undefined when the fine session lacks the strike, so the entry is left out of the granularity check.
 */
export function fineBarsFor(entry: StudyEntry, fine: ResearchSession, barMs: number): FineBars | undefined {
  const premium = legBars(fine, entry.trade.optionType, entry.trade.strike);
  if (premium === undefined || premium.length === 0) {
    return undefined;
  }
  return { premium: bucket(premium, barMs), spot: bucket(fine.spot, barMs) };
}

function merge(bars: readonly Candle[]): Candle {
  const first = bars[0] as Candle;
  const last = bars[bars.length - 1] as Candle;
  return {
    time: first.time,
    open: first.open,
    high: Math.max(...bars.map((bar) => bar.high)),
    low: Math.min(...bars.map((bar) => bar.low)),
    close: last.close,
    volume: bars.reduce((sum, bar) => sum + bar.volume, 0),
  };
}

function aggregate(bars: readonly Candle[], barMs: number): Candle[] {
  return [...bucket(bars, barMs).values()].map(merge);
}

/**
 * The same 1-minute dataset rebuilt as `minutes`-minute bars. The granularity check replays entries from this, so the
 * coarse and fine runs share one source and differ only in bar size.
 */
export function aggregateDataset(dataset: ResearchDataset, minutes: number): ResearchDataset {
  const barMs = minutes * 60_000;
  const byStrike = (legs: ResearchSession['calls']) => Object.fromEntries(Object.entries(legs).map(([strike, bars]) => [strike, aggregate(bars, barMs)]));
  const sessions = dataset.sessions.map((session) => ({ ...session, spot: aggregate(session.spot, barMs), calls: byStrike(session.calls), puts: byStrike(session.puts) }));
  return { ...dataset, barMinutes: minutes, sessions };
}

/**
 * A dataset at `minutes`-minute bars: as is when it already is, rebuilt when it is a finer whole divisor. 5-minute
 * rolling-option bars mix two strikes whenever spot crosses a strike inside the bar (docs/TRAILING_STOPS.md §12.2), so
 * 5-minute research should be rebuilt from 1-minute fetches.
 */
export function atBarMinutes(dataset: ResearchDataset, minutes: number): ResearchDataset {
  if (dataset.barMinutes === minutes) {
    return dataset;
  }
  if (minutes % dataset.barMinutes !== 0) {
    throw new Error(`dataset bars are ${dataset.barMinutes}-minute and cannot be rebuilt as ${minutes}-minute bars`);
  }
  return aggregateDataset(dataset, minutes);
}

import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import {
  buildSessions,
  parseDataset,
  parseRollingOptionResponse,
  pivotByStrike,
  type ResearchDataset,
  type ResearchSession,
} from '../src/research/dataset.js';
import { replayDataset, type CostModel, type ReplayConfig } from '../src/research/replay.js';
import { SeededRng } from '../src/research/rng.js';
import {
  bootstrapMeanR,
  chronologicalSplit,
  groupByDay,
  maxDrawdown,
  simulatePaths,
  summarize,
  wilsonInterval,
  type TradeSample,
} from '../src/research/stats.js';
import { bestSessionShare, dominanceCap, dominanceTest, holdoutBlockLength, meanWithoutBestSession, simulatedDominanceCap } from '../src/research/stats.js';
import { applyCostStress, DEFAULT_TIME_MACHINE_OPTIONS, formatReport, runTimeMachine } from '../src/research/timeMachine.js';
import { applyCostStressToCells, contextCells, formatCells, vixTerciles } from '../src/research/contextCells.js';
import { nominalMonthlyExpiry, nominalWeeklyExpiry } from '../src/time/calendar.js';
import { shiftDateKey } from '../src/time/ist.js';
import { bar, istEpoch } from './support/fixtures.js';

const DAY = '2026-10-12';
const NO_COSTS: CostModel = { halfSpreadPct: 0, stopSlippagePct: 0 };

const CONFIG: ReplayConfig = {
  barMinutes: 5,
  warmupSessions: 0,
  posture: 'scout',
  enabledStrategies: ['range'],
  strategy: {
    orbMinutes: 15,
    barMinutes: 5,
    supertrendPeriod: 10,
    supertrendMultiplier: 3,
    emaFast: 9,
    emaSlow: 21,
    entryStartMinute: 9 * 60 + 30,
    entryEndMinute: 14 * 60 + 30,
    sessionOpenMinute: 9 * 60 + 15,
  },
  contextGate: false,
  structureExit: false,
  strikeOffsetSteps: 0,
  entryLimitBufferPct: 0,
  expiryDayEntryCutoffMinute: 13 * 60,
  exits: {
    stopLossPct: 30,
    targetRr: 2,
    maxHoldMinutes: 400,
    flattenByMinute: 15 * 60 + 15,
    cooldownSeconds: 0,
    trailingJumpPct: 0,
    breakevenAtRr: 1,
    runnerMode: false,
  },
  capital: { inr: 100_000, maxRiskPerTradePct: 2, maxDailyLossPct: 5, maxTradesPerDay: 3, maxLotsPerOrder: 15, allInRiskPolicy: 'off' },
};

function hhmm(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

/** 09:15 to 15:25, every five minutes. */
const SESSION_MINUTES = Array.from({ length: 75 }, (_, i) => 9 * 60 + 15 + i * 5);

/**
 * Spot sits at 100 through the opening range (high 100.5), the 09:30 bar closes at 101 (a bullish ORB cross, so
 * the CE 100 is bought at the 09:35 open), and it stays at 101 for the rest of the day.
 */
function spotBars(date: string, closeAt: (minute: number) => number = (minute) => (minute < 9 * 60 + 30 ? 100 : 101)): Candle[] {
  return SESSION_MINUTES.map((minute) => {
    const close = closeAt(minute);
    return bar(istEpoch(date, hhmm(minute)), close, close + 0.5, close - 0.5, close);
  });
}

type OptionOverrides = Readonly<Record<string, readonly [number, number, number, number] | null>>;

/** Flat premium bars at 10, with per-clock overrides. `null` removes the bar. */
function premiumBars(date: string, overrides: OptionOverrides = {}): Candle[] {
  const bars: Candle[] = [];
  for (const minute of SESSION_MINUTES) {
    const clock = hhmm(minute);
    const override = overrides[clock];
    if (override === null) {
      continue;
    }
    const [open, high, low, close] = override ?? [10, 10, 10, 10];
    bars.push(bar(istEpoch(date, clock), open, high, low, close));
  }
  return bars;
}

function session(date: string, overrides: OptionOverrides = {}): ResearchSession {
  return {
    date,
    lotSize: 50,
    tickSize: 0.05,
    strikeStep: 5,
    spot: spotBars(date),
    calls: { '95': premiumBars(date), '100': premiumBars(date, overrides), '105': premiumBars(date) },
    puts: { '95': premiumBars(date), '100': premiumBars(date), '105': premiumBars(date) },
  };
}

function dataset(sessions: ResearchSession[]): ResearchDataset {
  return { version: 1, underlying: 'NIFTY', optionSegment: 'NSE_FNO', barMinutes: 5, source: { kind: 'fixture' }, sessions };
}

function days(count: number, overrides: OptionOverrides): ResearchSession[] {
  return Array.from({ length: count }, (_, i) => session(shiftDateKey(DAY, i), overrides));
}

describe('SeededRng', () => {
  it('repeats the same sequence for the same seed and stays in range', () => {
    const a = new SeededRng(19);
    const b = new SeededRng(19);
    const draws = Array.from({ length: 1_000 }, () => a.next());
    assert.deepEqual(draws, Array.from({ length: 1_000 }, () => b.next()));
    assert.ok(draws.every((value) => value >= 0 && value < 1));
    assert.notDeepEqual(draws.slice(0, 5), Array.from({ length: 5 }, ((rng) => () => rng.next())(new SeededRng(20))));
  });

  it('rejects a seed that is not a 32-bit unsigned integer', () => {
    assert.throws(() => new SeededRng(-1), RangeError);
    assert.throws(() => new SeededRng(1.5), RangeError);
  });
});

describe('rolling option parsing', () => {
  const t0 = istEpoch(DAY, '09:15') / 1_000;
  const t1 = istEpoch(DAY, '09:20') / 1_000;

  it('reads the ce column block and tags each bar with its real strike', () => {
    const raw = { data: { ce: { open: [10, 11], high: [12, 12], low: [9, 10], close: [11, 11.5], volume: [5, 6], strike: [100, 105], timestamp: [t0, t1] }, pe: null } };
    const bars = parseRollingOptionResponse(raw, 'CE', false);
    assert.equal(bars.length, 2);
    assert.equal(bars[1]?.strike, 105);
    assert.equal(bars[0]?.time, t0 * 1_000);
  });

  it('returns no bars for a side the response names as null, and refuses a missing side', () => {
    assert.deepEqual(parseRollingOptionResponse({ data: { ce: null, pe: null } }, 'CE', false), []);
    assert.throws(() => parseRollingOptionResponse({ data: { calls: {} } }, 'CE', false), /no data\.ce \(found: calls\)/);
    assert.throws(() => parseRollingOptionResponse([{ timestamp: t0, close: 10 }], 'PE', false), /no data\.pe/);
  });

  it('refuses mismatched columns and impossible OHLC, and skips zero prints', () => {
    const base = { open: [10], high: [12], low: [9], close: [11], strike: [100], timestamp: [t0] };
    assert.throws(() => parseRollingOptionResponse({ data: { ce: { ...base, close: [11, 12] } } }, 'CE', false), /column "close"/);
    assert.throws(() => parseRollingOptionResponse({ data: { ce: { ...base, high: [8] } } }, 'CE', false), /inconsistent OHLC/);
    assert.throws(() => parseRollingOptionResponse({ data: { ce: { ...base, strike: undefined } } }, 'CE', false), /column "strike"/);
    assert.deepEqual(parseRollingOptionResponse({ data: { ce: { ...base, open: [0], low: [0] } } }, 'CE', false), []);
  });

  it('stitches one strike across ATM offsets and counts disagreeing duplicates', () => {
    const atm = [{ time: 1, open: 10, high: 10, low: 10, close: 10, volume: 0, strike: 100 }, { time: 2, open: 8, high: 8, low: 8, close: 8, volume: 0, strike: 105 }];
    const atmMinus1 = [{ time: 2, open: 12, high: 12, low: 12, close: 12, volume: 0, strike: 100 }, { time: 1, open: 9, high: 9, low: 9, close: 9, volume: 0, strike: 95 }];
    const conflicting = [{ time: 1, open: 11, high: 11, low: 11, close: 11, volume: 0, strike: 100 }];
    const { byStrike, conflicts } = pivotByStrike([atm, atmMinus1, conflicting]);
    assert.deepEqual(byStrike.get(100)?.map((candle) => [candle.time, candle.close]), [[1, 10], [2, 12]]);
    assert.equal(conflicts, 1);
  });

  it('keeps IV and OI through parsing and the strike pivot when the response has them', () => {
    const raw = { data: { ce: { open: [10], high: [12], low: [9], close: [11], strike: [100], iv: [18.5], oi: [4200], timestamp: [t0] } } };
    const { byStrike } = pivotByStrike([parseRollingOptionResponse(raw, 'CE', false)]);
    assert.deepEqual(byStrike.get(100)?.map((candle) => [candle.iv, candle.oi]), [[18.5, 4200]]);
  });
});

describe('research dataset validation', () => {
  it('accepts a well-formed dataset', () => {
    assert.equal(parseDataset(JSON.parse(JSON.stringify(dataset([session(DAY)])))).sessions.length, 1);
  });

  it('keeps the SDK and parser versions a dataset was fetched with, through a reload', () => {
    const fetched = JSON.parse(JSON.stringify(dataset([session(DAY)])));
    fetched.source = { ...fetched.source, provenance: { sdkVersion: '2.0.1', parserVersion: 'rollingoption-v1', responseSchemaVersion: 'rollingoption-layout-1' } };
    assert.deepEqual(parseDataset(fetched).source.provenance, { sdkVersion: '2.0.1', parserVersion: 'rollingoption-v1', responseSchemaVersion: 'rollingoption-layout-1' });
  });

  it('accepts a dataset fetched before provenance was recorded, and reports none', () => {
    assert.equal(parseDataset(JSON.parse(JSON.stringify(dataset([session(DAY)])))).source.provenance, undefined);
  });

  it('refuses bars outside the session, off the grid, out of order, or on another day', () => {
    const outside = session(DAY);
    const bad = (mutate: (bars: Candle[]) => Candle[]): ResearchDataset => dataset([{ ...outside, spot: mutate([...outside.spot]) }]);
    assert.throws(() => parseDataset(bad((bars) => [bar(istEpoch(DAY, '09:10'), 1, 1, 1, 1), ...bars])), /outside the session/);
    assert.throws(() => parseDataset(bad((bars) => [bar(istEpoch(DAY, '09:17'), 1, 1, 1, 1)])), /off the 5-minute grid/);
    assert.throws(() => parseDataset(bad((bars) => [...bars].reverse())), /strictly ascending/);
    assert.throws(() => parseDataset(bad(() => [bar(istEpoch('2026-10-13', '09:15'), 1, 1, 1, 1)])), /not 2026-10-12/);
    assert.throws(() => parseDataset(bad(() => [bar(istEpoch(DAY, '09:15'), 5, 4, 3, 4)])), /inconsistent OHLC/);
  });

  it('refuses duplicate or descending session dates', () => {
    assert.throws(() => parseDataset(dataset([session(DAY), session(DAY)])), /strictly ascending by date/);
  });

  it('splits fetched bars into sessions and derives the strike step', () => {
    const sessions = buildSessions({
      spot: [...spotBars(DAY), ...spotBars('2026-10-13')],
      calls: new Map([[100, premiumBars(DAY)], [150, premiumBars(DAY)], [200, premiumBars('2026-10-13')]]),
      puts: new Map([[50, premiumBars(DAY)]]),
      lotSize: 75,
      tickSize: 0.05,
      fromDate: DAY,
      toDate: DAY,
    });
    assert.equal(sessions.length, 1);
    assert.equal(sessions[0]?.strikeStep, 50);
    assert.deepEqual(Object.keys(sessions[0]?.calls ?? {}).sort(), ['100', '150']);
  });
});

describe('historical replay', () => {
  it('buys the ATM CE at the next bar open and books the target', () => {
    const result = replayDataset(dataset([session(DAY, { '09:40': [10, 16.5, 10, 16] })]), CONFIG, NO_COSTS);
    assert.equal(result.signals, 1);
    assert.equal(result.trades.length, 1);
    const trade = result.trades[0];
    assert.ok(trade !== undefined);
    assert.equal(trade.optionType, 'CE');
    assert.equal(trade.strike, 100);
    assert.equal(trade.entryTime, istEpoch(DAY, '09:35'));
    assert.equal(trade.entryPrice, 10);
    assert.equal(trade.initialStopPrice, 7);
    assert.equal(trade.targetPrice, 16);
    // 2% of 1,00,000 = 2,000 risk; 3 points × 50 per lot = 150; 13 lots.
    assert.equal(trade.lots, 13);
    assert.equal(trade.exitReason, 'TARGET');
    assert.equal(trade.exitPrice, 16);
    assert.equal(trade.grossPnlInr, 3_900);
    assert.ok(trade.chargesInr > 40, 'charges include two ₹20 brokerage legs');
    assert.equal(trade.netPnlInr, Number((3_900 - trade.chargesInr).toFixed(2)));
  });

  it('counts a bar that touches both legs as the stop', () => {
    const [trade] = replayDataset(dataset([session(DAY, { '09:40': [10, 17, 6.5, 12] })]), CONFIG, NO_COSTS).trades;
    assert.equal(trade?.exitReason, 'STOP_LOSS');
    assert.equal(trade?.exitPrice, 7);
    assert.equal(trade?.ambiguousBar, true);
  });

  it('fills a gap through the stop at the open, not at the stop', () => {
    const [trade] = replayDataset(dataset([session(DAY, { '09:40': [5, 5.5, 4.5, 5] })]), CONFIG, NO_COSTS).trades;
    assert.equal(trade?.exitReason, 'STOP_LOSS');
    assert.equal(trade?.exitPrice, 5);
    assert.equal(trade?.gapThroughStop, true);
    assert.ok((trade?.r ?? 0) < -1, 'a gap loses more than 1R');
  });

  it('flattens at FLATTEN_BY when neither leg is hit', () => {
    const [trade] = replayDataset(dataset([session(DAY)]), CONFIG, NO_COSTS).trades;
    assert.equal(trade?.exitReason, 'EOD_FLATTEN');
    assert.equal(trade?.exitTime, istEpoch(DAY, '15:15'));
  });

  it('applies the time stop from the entry time', () => {
    const [trade] = replayDataset(dataset([session(DAY)]), { ...CONFIG, exits: { ...CONFIG.exits, maxHoldMinutes: 30 } }, NO_COSTS).trades;
    assert.equal(trade?.exitReason, 'TIME_STOP');
    assert.equal(trade?.exitTime, istEpoch(DAY, '10:05'));
  });

  it('removes a trade whose held strike has a missing bar, and drops a signal with no entry bar', () => {
    const gap = replayDataset(dataset([session(DAY, { '10:00': null })]), CONFIG, NO_COSTS);
    assert.equal(gap.trades[0]?.exitReason, 'DATA_GAP');
    const noEntry = replayDataset(dataset([session(DAY, { '09:35': null })]), CONFIG, NO_COSTS);
    assert.equal(noEntry.trades.length, 0);
    assert.equal(noEntry.drops['NO_OPTION_DATA'], 1);
  });

  it('prices entries at the ask and exits at the bid under a spread', () => {
    const [trade] = replayDataset(dataset([session(DAY, { '09:40': [10, 20, 10, 18] })]), CONFIG, { halfSpreadPct: 1, stopSlippagePct: 0 }).trades;
    assert.equal(trade?.entryPrice, 10.1);
    assert.equal(trade?.exitReason, 'TARGET');
  });

  it('skips the trade when one lot does not fit the risk budget', () => {
    const result = replayDataset(dataset([session(DAY)]), { ...CONFIG, capital: { ...CONFIG.capital, inr: 1_000 } }, NO_COSTS);
    assert.equal(result.trades.length, 0);
    assert.equal(result.drops['RISK_BUDGET_TOO_SMALL'], 1);
  });

  it('honours the expiry-day entry cutoff when the session records its expiry', () => {
    const expiryDay = { ...session(DAY), expiry: DAY };
    const result = replayDataset(dataset([expiryDay]), { ...CONFIG, expiryDayEntryCutoffMinute: 9 * 60 + 30 }, NO_COSTS);
    assert.equal(result.drops['EXPIRY_DAY_CUTOFF'], 1);
  });

  it('derives the weekly expiry day for a rolling-option dataset that records no expiry', () => {
    const tuesday = session('2026-10-13');
    const rolling = { ...dataset([session('2026-10-12'), tuesday]), source: { kind: 'dhan_rollingoption' as const, expiryFlag: 'WEEK', expiryCode: 1 } };
    const result = replayDataset(rolling, { ...CONFIG, expiryDayEntryCutoffMinute: 9 * 60 + 30 }, NO_COSTS);
    assert.equal(result.drops['EXPIRY_DAY_CUTOFF'], 1, 'NIFTY expires on Tuesday');
    const nextWeek = replayDataset({ ...rolling, source: { ...rolling.source, expiryCode: 2 } }, { ...CONFIG, expiryDayEntryCutoffMinute: 9 * 60 + 30 }, NO_COSTS);
    assert.equal(nextWeek.drops['EXPIRY_DAY_CUTOFF'], undefined, 'the next-week contract does not expire today');
  });

  it('runs the live gate: MAX_TRADES_PER_DAY 0 is unlimited, 1 stops the second entry', () => {
    // Crosses the opening-range high at 09:30, falls back inside it, and crosses again at 10:30.
    const twice = (minute: number): number => (minute < 9 * 60 + 30 ? 100 : minute < 9 * 60 + 35 ? 101 : minute < 10 * 60 + 30 ? 100 : 101);
    const day = { ...session(DAY, { '09:40': [10, 16.5, 10, 16], '10:40': [10, 16.5, 10, 16] }), spot: spotBars(DAY, twice) };
    const unlimited = replayDataset(dataset([day]), { ...CONFIG, capital: { ...CONFIG.capital, maxTradesPerDay: 0 } }, NO_COSTS);
    assert.equal(unlimited.trades.length, 2);
    const capped = replayDataset(dataset([day]), { ...CONFIG, capital: { ...CONFIG.capital, maxTradesPerDay: 1 } }, NO_COSTS);
    assert.equal(capped.trades.length, 1);
    assert.equal(capped.drops['TRADE_COUNT_LIMIT'], 1);
  });

  it('blocks entries for COOLDOWN_SECONDS after an exit', () => {
    const twice = (minute: number): number => (minute < 9 * 60 + 30 ? 100 : minute < 9 * 60 + 35 ? 101 : minute < 10 * 60 + 30 ? 100 : 101);
    const day = { ...session(DAY, { '09:40': [10, 16.5, 10, 16], '10:40': [10, 16.5, 10, 16] }), spot: spotBars(DAY, twice) };
    const result = replayDataset(dataset([day]), { ...CONFIG, exits: { ...CONFIG.exits, cooldownSeconds: 3_600 } }, NO_COSTS);
    assert.equal(result.trades.length, 1);
    assert.equal(result.drops['COOLDOWN_ACTIVE'], 1);
  });

  it('stops entering once the day has lost its daily limit', () => {
    const twice = (minute: number): number => (minute < 9 * 60 + 30 ? 100 : minute < 9 * 60 + 35 ? 101 : minute < 10 * 60 + 30 ? 100 : 101);
    const day = { ...session(DAY, { '09:40': [5, 5, 5, 5], '10:40': [10, 16.5, 10, 16] }), spot: spotBars(DAY, twice) };
    const result = replayDataset(dataset([day]), { ...CONFIG, capital: { ...CONFIG.capital, maxDailyLossPct: 2 } }, NO_COSTS);
    assert.equal(result.trades.length, 1);
    assert.equal(result.drops['KILL_SWITCH_ACTIVE'], 1);
  });

  it('refuses a dataset whose bar size differs from BAR_MINUTES', () => {
    assert.throws(() => replayDataset({ ...dataset([session(DAY)]), barMinutes: 15 }, CONFIG, NO_COSTS), /BAR_MINUTES/);
  });

  it('is deterministic', () => {
    const data = dataset(days(5, { '10:00': [10, 16.5, 10, 16] }));
    assert.deepEqual(replayDataset(data, CONFIG, NO_COSTS), replayDataset(data, CONFIG, NO_COSTS));
  });
});

describe('statistics', () => {
  const sample = (date: string, r: number): TradeSample => ({ date, r, netPnlInr: r * 1_000, exitReason: r > 0 ? 'TARGET' : 'STOP_LOSS' });

  it('computes the Wilson interval', () => {
    const interval = wilsonInterval(5, 10);
    assert.ok(Math.abs(interval.low - 0.2366) < 1e-3 && Math.abs(interval.high - 0.7634) < 1e-3);
    assert.deepEqual(wilsonInterval(0, 0), { low: 0, high: 1 });
    assert.equal(wilsonInterval(0, 20).low, 0);
  });

  it('measures drawdown peak to trough', () => {
    assert.equal(maxDrawdown([100, -50, -80, 30]), 130);
    assert.equal(maxDrawdown([10, 20]), 0);
  });

  it('summarises bracket outcomes and break-even win rate', () => {
    const summary = summarize([sample('a', 2), sample('a', -1), sample('b', -1)], 2);
    assert.equal(summary.targetFirst.rate, 0.3333);
    assert.equal(summary.stopFirst.rate, 0.6667);
    assert.equal(summary.breakevenWinRate, 0.3333);
    assert.equal(summary.meanR, 0);
  });

  it('measures the holdout mean without its best session, so one lucky day cannot carry the result (OTA-308)', () => {
    const dates = ['2026-12-01', '2026-12-02', '2026-12-03'];
    const days = groupByDay(dates, [sample(dates[0] as string, 5), sample(dates[1] as string, -1), sample(dates[2] as string, -1)]);
    assert.equal(meanWithoutBestSession(days), -1, 'removing the +5 day leaves two losing days');
    assert.equal(meanWithoutBestSession([]), undefined);
  });

  it('caps the share of profit any one holdout session can supply (OTA-308 eligibility)', () => {
    const dates = ['2026-12-01', '2026-12-02', '2026-12-03', '2026-12-04'];
    const lumpy = groupByDay(dates, [sample(dates[0] as string, 6), sample(dates[1] as string, 1), sample(dates[2] as string, 1), sample(dates[3] as string, -2)]);
    assert.ok((bestSessionShare(lumpy) ?? 0) > 0.6, 'one session supplies 6 of 8 units of profit');
    const even = groupByDay(dates, [sample(dates[0] as string, 1), sample(dates[1] as string, 1), sample(dates[2] as string, 1), sample(dates[3] as string, 1)]);
    assert.equal(bestSessionShare(even), 0.25);
    const losing = groupByDay(dates, [sample(dates[0] as string, -1), sample(dates[1] as string, -2), sample(dates[2] as string, -1), sample(dates[3] as string, -1)]);
    assert.equal(bestSessionShare(losing), undefined, 'no profit, no share');
  });

  it('derives the profit-share cap from the holdout\'s own winners, so a tight holdout gets a tight cap (OTA-308)', () => {
    // Equal winners have no spread, so the only fair share is 1/W, and any excess is dominance.
    assert.equal(simulatedDominanceCap(10, 1, 0, 19), 1 / 10);
    // Spread raises the cap: a dispersed set of winners can legitimately have a larger largest session.
    const tight = simulatedDominanceCap(15, 1, 0.1, 19) ?? 0;
    const loose = simulatedDominanceCap(15, 1, 0.6, 19) ?? 0;
    assert.ok(tight > 1 / 15 && loose > tight, 'the cap widens with the spread');
    // More winners lower the fair share, so the cap falls with the number of winners at a given relative spread.
    assert.ok((simulatedDominanceCap(30, 1, 0.5, 19) ?? 1) < (simulatedDominanceCap(10, 1, 0.5, 19) ?? 0));
    // Deterministic for a seed.
    assert.equal(simulatedDominanceCap(15, 1, 0.5, 19), simulatedDominanceCap(15, 1, 0.5, 19));
  });

  it('passes a mildly dispersed holdout and refuses one session that carries it', () => {
    const dates = Array.from({ length: 10 }, (_, i) => `2026-12-${String(i + 1).padStart(2, '0')}`);
    const winners = [1.2, 1.5, 1.1, 1.4, 1.3, 1.6, 1.2, 1.5, 1.3, 1.4];
    const mild = groupByDay(dates, winners.map((r, i) => sample(dates[i] as string, r)));
    const mildTest = dominanceTest(mild, 19);
    assert.equal(mildTest.passes, true, `share ${mildTest.share} within cap ${mildTest.cap}`);
    const carried = groupByDay(dates, [...winners.slice(0, 9), 8.0].map((r, i) => sample(dates[i] as string, r)));
    assert.equal(dominanceTest(carried, 19).passes, false, 'one 8R session is far beyond what these winners allow');
  });

  it('refuses a cap when there are fewer than two winning sessions to compare', () => {
    assert.equal(dominanceCap([2.0], 19), undefined);
    const dates = ['2026-12-01', '2026-12-02'];
    assert.equal(dominanceTest(groupByDay(dates, [sample(dates[0] as string, 1), sample(dates[1] as string, -1)]), 19).passes, false);
  });

  it('blocks the holdout bootstrap in at least five sessions, so dependence within a trading week survives', () => {
    assert.equal(holdoutBlockLength(30), 5, 'the cube-root rule alone would give 3');
    assert.equal(holdoutBlockLength(1000), 10);
  });

  it('bootstraps whole days, deterministically, including days with no trade', () => {
    const dates = Array.from({ length: 40 }, (_, i) => shiftDateKey(DAY, i));
    const winners = groupByDay(dates, dates.map((date) => sample(date, 1)));
    const first = bootstrapMeanR(winners, { iterations: 500, seed: 7 });
    assert.deepEqual(first, bootstrapMeanR(winners, { iterations: 500, seed: 7 }));
    assert.equal(first.probMeanRNonPositive, 0);
    assert.ok(first.meanRCi95.low > 0);

    const sparse = groupByDay(dates, [sample(dates[0] as string, 1)]);
    assert.ok(bootstrapMeanR(sparse, { iterations: 500, seed: 7 }).emptyResamples > 0);
  });

  it('puts a mixed sample interval across zero', () => {
    const dates = Array.from({ length: 40 }, (_, i) => shiftDateKey(DAY, i));
    const mixed = groupByDay(dates, dates.map((date, i) => sample(date, i % 2 === 0 ? 1 : -1)));
    const result = bootstrapMeanR(mixed, { iterations: 2_000, seed: 19 });
    assert.ok(result.meanRCi95.low < 0 && result.meanRCi95.high > 0);
  });

  it('simulates path drawdowns over a horizon', () => {
    const dates = Array.from({ length: 30 }, (_, i) => shiftDateKey(DAY, i));
    const losers = groupByDay(dates, dates.map((date) => sample(date, -1)));
    const paths = simulatePaths(losers, { paths: 200, seed: 1, horizonDays: 10, drawdownAlarmInr: 5_000 });
    assert.equal(paths.probLoss, 1);
    assert.equal(paths.maxDrawdownInr.p50, 10_000);
    assert.equal(paths.probDrawdownAtLeast.probability, 1);
  });

  it('splits chronologically and refuses a trade outside the replayed days', () => {
    const split = chronologicalSplit([{ date: '1' }, { date: '2' }, { date: '3' }, { date: '4' }, { date: '5' }], 0.6);
    assert.deepEqual(split.inSample.map((d) => d.date), ['1', '2', '3']);
    assert.throws(() => groupByDay(['a'], [sample('b', 1)]), /outside the replayed days/);
    assert.throws(() => chronologicalSplit([], 1), RangeError);
  });
});

describe('weekly expiry calendar (look-ahead free)', () => {
  it('gives each session the next expiry weekday on or after its date, from its own date alone', () => {
    assert.equal(nominalWeeklyExpiry('NIFTY', '2026-10-12'), '2026-10-13', 'a Monday trades against that Tuesday');
    assert.equal(nominalWeeklyExpiry('NIFTY', '2026-10-13'), '2026-10-13', 'the expiry day is its own expiry');
    assert.equal(nominalWeeklyExpiry('NIFTY', '2026-10-14'), '2026-10-20', 'a Wednesday trades against the next Tuesday');
    assert.equal(nominalWeeklyExpiry('SENSEX', '2026-10-23'), '2026-10-29', 'SENSEX expires on Thursday, so a Friday waits a week');
  });

  it('does not look ahead: a holiday on the expiry weekday does not move an earlier session', () => {
    // Tue 20 Oct is a holiday. Monday 19 Oct cannot know that from its own date, so its expiry is the nominal Tuesday.
    assert.equal(nominalWeeklyExpiry('NIFTY', '2026-10-19'), '2026-10-20');
  });

  it('has no rule for an index whose expiry convention is unverified', () => {
    assert.equal(nominalWeeklyExpiry('BANKNIFTY', '2026-10-13'), undefined);
  });
});

describe('monthly expiry calendar (look-ahead free)', () => {
  it('gives each session the last expiry weekday of its month, or of the next month once that has passed', () => {
    // October 2026: Tuesdays fall on 6, 13, 20 and 27.
    assert.equal(nominalMonthlyExpiry('BANKNIFTY', '2026-10-01'), '2026-10-27');
    assert.equal(nominalMonthlyExpiry('BANKNIFTY', '2026-10-27'), '2026-10-27', 'the expiry day is its own expiry');
    assert.equal(nominalMonthlyExpiry('BANKNIFTY', '2026-10-28'), '2026-11-24', 'the day after rolls to the next month');
    assert.equal(nominalMonthlyExpiry('BANKNIFTY', '2026-12-30'), '2027-01-26', 'the roll crosses a year end');
    // March 2026 has five Tuesdays; the last is the 31st.
    assert.equal(nominalMonthlyExpiry('BANKNIFTY', '2026-03-25'), '2026-03-31');
  });

  it('has no rule for an index whose monthly convention is not recorded', () => {
    assert.equal(nominalMonthlyExpiry('SENSEX', '2026-10-13'), undefined);
  });
});

describe('replay: expiry limits', () => {
  const monthly = (dates: string[]): ResearchDataset => ({
    ...dataset(dates.map((date) => session(date))),
    underlying: 'BANKNIFTY',
    source: { kind: 'dhan_rollingoption' as const, expiryFlag: 'MONTH', expiryCode: 1 },
  });

  it('should apply the expiry-day cutoff to a monthly rolling dataset on its last Tuesday', () => {
    const result = replayDataset(monthly(['2026-10-26', '2026-10-27']), { ...CONFIG, expiryDayEntryCutoffMinute: 9 * 60 + 30 }, NO_COSTS);
    assert.equal(result.drops['EXPIRY_DAY_CUTOFF'], 1);
    assert.equal(result.trades.length, 1);
  });

  it('should take no entry on a session whose contract is further from expiry than MAX_DAYS_TO_EXPIRY', () => {
    // 2026-10-12 is 15 days from the 27 October expiry; 2026-10-21 is 6 days from it.
    const result = replayDataset(monthly(['2026-10-12', '2026-10-21']), { ...CONFIG, minDaysToExpiry: 0, maxDaysToExpiry: 6 }, NO_COSTS);
    assert.deepEqual(result.trades.map((trade) => trade.date), ['2026-10-21']);
    assert.equal(result.drops['EXPIRY_OUT_OF_RANGE'], 1);
  });

  it('should take no entry on a session closer to expiry than MIN_DAYS_TO_EXPIRY', () => {
    const result = replayDataset(monthly(['2026-10-26', '2026-10-27']), { ...CONFIG, minDaysToExpiry: 1, maxDaysToExpiry: 6 }, NO_COSTS);
    assert.deepEqual(result.trades.map((trade) => trade.date), ['2026-10-26']);
    assert.equal(result.drops['EXPIRY_OUT_OF_RANGE'], 1);
  });

  it('should treat a MAX_DAYS_TO_EXPIRY of zero as no upper limit, as the live selector does', () => {
    const result = replayDataset(monthly(['2026-10-12']), { ...CONFIG, minDaysToExpiry: 0, maxDaysToExpiry: 0 }, NO_COSTS);
    assert.equal(result.trades.length, 1);
  });

  it('should not filter a session whose expiry is unknown, and say so', () => {
    const result = replayDataset(dataset([session(DAY)]), { ...CONFIG, minDaysToExpiry: 0, maxDaysToExpiry: 1 }, NO_COSTS);
    assert.equal(result.trades.length, 1);
    assert.ok(result.divergences.some((line) => /expiry limits are not applied/.test(line)));
  });

  it('should leave a weekly dataset unchanged under the paper profile limits of 0 to 6 days', () => {
    const week = ['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16'];
    const weekly = { ...dataset(week.map((date) => session(date))), source: { kind: 'dhan_rollingoption' as const, expiryFlag: 'WEEK', expiryCode: 1 } };
    const limited = replayDataset(weekly, { ...CONFIG, minDaysToExpiry: 0, maxDaysToExpiry: 6 }, NO_COSTS);
    assert.deepEqual(limited.trades, replayDataset(weekly, CONFIG, NO_COSTS).trades);
    assert.equal(limited.drops['EXPIRY_OUT_OF_RANGE'], undefined);
  });
});

describe('context cells', () => {
  const options = { iterations: 500, seed: 19, minTrades: 30, splitFraction: 0.6, priorRuns: 0, minHoldoutDays: 30 };

  it('tags each replayed trade with the context at its signal', () => {
    const result = replayDataset(dataset([session(DAY, { '10:00': [10, 16.5, 10, 16] })]), CONFIG, NO_COSTS);
    const context = result.trades[0]?.context;
    assert.equal(context?.timeBucket, 'OPEN');
    assert.equal(context?.expiryDay, false);
    assert.ok(['TRENDING', 'RANGING'].includes(context?.regime ?? ''));
    assert.ok(['WITH', 'AGAINST', 'NEUTRAL'].includes(context?.trendAlignment ?? ''));
    // OTA-309: the new features are present, typed, and never a guessed chain bias.
    assert.ok(['LOW', 'MID', 'HIGH', 'UNKNOWN'].includes(context?.volatility ?? ''));
    assert.ok(['WITH', 'AGAINST', 'NEUTRAL', 'UNKNOWN'].includes(context?.structureAlignment ?? ''));
    assert.ok(['EXPIRY', 'NEAR', 'FAR', 'UNKNOWN'].includes(context?.expiryBucket ?? ''));
    assert.equal(context?.chainBias, 'UNKNOWN');
  });

  it('reports each strategy per context value, and corrects the bar for every cell tested', () => {
    const result = replayDataset(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS);
    const report = contextCells(result, new Map(), options);
    const open = report.cells.find((cell) => cell.key === 'range | timeBucket=OPEN');
    assert.equal(open?.trades, 80);
    assert.equal(open?.verdict, 'EDGE_SUPPORTED');
    assert.equal(report.testsCounted, report.cells.length);
    assert.match(formatCells(report), /range \| timeBucket=OPEN/);
    assert.ok(report.cells.some((cell) => cell.key.includes(' | volatility=')), 'volatility is a cell dimension');
    assert.ok(!report.cells.some((cell) => cell.key.includes('chainBias')), 'chainBias is not a cell dimension');
  });

  it('says INSUFFICIENT_EVIDENCE for a cell below the minimum trade count', () => {
    const result = replayDataset(dataset(days(10, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS);
    const report = contextCells(result, new Map(), options);
    assert.ok(report.cells.every((cell) => cell.verdict === 'INSUFFICIENT_EVIDENCE'));
  });

  it('says INSUFFICIENT_EVIDENCE for a cell whose holdout spans too few sessions, even with enough trades', () => {
    const result = replayDataset(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS);
    const report = contextCells(result, new Map(), { ...options, minHoldoutDays: 50 });
    assert.ok(report.cells.every((cell) => cell.verdict === 'INSUFFICIENT_EVIDENCE'));
  });

  it('downgrades an EDGE_SUPPORTED cell that fails a cost stress, and never upgrades one', () => {
    const winners = replayDataset(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS);
    const losers = replayDataset(dataset(days(80, { '10:00': [10, 10, 6.5, 7] })), CONFIG, NO_COSTS);
    const base = contextCells(winners, new Map(), options);
    const open = applyCostStressToCells(base, [{ label: 'stop slippage 2x', report: contextCells(losers, new Map(), options) }]).cells.find(
      (cell) => cell.key === 'range | timeBucket=OPEN',
    );
    assert.equal(open?.verdict, 'NO_TRADE');
    const kept = applyCostStressToCells(base, [{ label: 'half-spread 1%', report: contextCells(winners, new Map(), options) }]);
    assert.ok(kept.cells.some((cell) => cell.verdict === 'EDGE_SUPPORTED'));
  });

  it('charges earlier runs on the same data against the significance bar', () => {
    const result = replayDataset(dataset(days(50, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS);
    const fresh = contextCells(result, new Map(), options);
    const reused = contextCells(result, new Map(), { ...options, priorRuns: 9 });
    assert.equal(reused.testsCounted, fresh.testsCounted * 10);
  });

});

describe('VIX terciles (look-ahead free)', () => {
  const day = (index: number) => shiftDateKey('2025-01-02', index);
  /** One VIX bar per calendar day, opening at the given value. */
  const vixSeries = (values: readonly number[]): Candle[] => values.map((open, index) => bar(istEpoch(day(index), '09:15'), open, open, open, open));

  it('tags a day from earlier sessions only: later days cannot move its tag', () => {
    // Earlier days: 66 below the tested value of 50, 14 above it. The tested day sits on the 67th-percentile boundary of
    // a full-sample rank, so whichever way the later days fall, a full-sample rank would move it.
    const earlier = Array.from({ length: 80 }, (_, index) => (index < 66 ? 10 + index * 0.1 : 60 + index * 0.1));
    const everyDay = Array.from({ length: 100 }, (_, index) => day(index));
    const laterHigh = vixTerciles(vixSeries([...earlier, 50, ...Array(19).fill(1000)]), everyDay).get(day(80));
    const laterLow = vixTerciles(vixSeries([...earlier, 50, ...Array(19).fill(1)]), everyDay).get(day(80));
    assert.deepEqual(laterHigh, laterLow, 'the later days changed the tag');
    assert.equal(laterHigh?.vix, 'HIGH', '66 of 80 earlier sessions are below it');
  });

  it('tags nothing below the minimum history, and nothing on a day without VIX', () => {
    const tags = vixTerciles(vixSeries(Array.from({ length: 80 }, (_, index) => 10 + index)), [day(59), day(60), day(200)]);
    assert.equal(tags.has(day(59)), false, '59 earlier sessions is below the minimum');
    assert.equal(tags.has(day(60)), true, '60 earlier sessions is the minimum');
    assert.equal(tags.has(day(200)), false, 'no VIX on that day');
  });

  it('ranks a rising VIX HIGH and a falling VIX LOW once there is history', () => {
    const rising = vixTerciles(vixSeries(Array.from({ length: 100 }, (_, index) => 10 + index)), [day(99)]);
    assert.equal(rising.get(day(99))?.vix, 'HIGH');
    const falling = vixTerciles(vixSeries(Array.from({ length: 100 }, (_, index) => 200 - index)), [day(99)]);
    assert.equal(falling.get(day(99))?.vix, 'LOW');
  });
});

describe('dataset quality', () => {
  it('counts missing spot bars and weekdays with no session', () => {
    const monday = session('2026-10-12');
    const gappy = { ...session('2026-10-14'), spot: spotBars('2026-10-14').filter((_, index) => index < 10 || index >= 13) };
    const report = runTimeMachine(dataset([monday, gappy]), CONFIG, NO_COSTS, [], { ...DEFAULT_TIME_MACHINE_OPTIONS, iterations: 100, drawdownAlarmInr: 5_000 });
    assert.deepEqual(report.dataQuality, { spotBarsMissing: 3, sessionsWithSpotGaps: 1, weekdaysWithoutSession: 1 });
    assert.match(formatReport(report), /Data quality: 3 spot bars missing across 1 sessions; 1 weekdays without a session/);
  });
});

describe('time machine verdict', () => {
  const options = { ...DEFAULT_TIME_MACHINE_OPTIONS, iterations: 500, drawdownAlarmInr: 5_000 };

  it('says INSUFFICIENT_EVIDENCE below the minimum trade count', () => {
    const report = runTimeMachine(dataset(days(10, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS, [], options);
    assert.equal(report.verdict, 'INSUFFICIENT_EVIDENCE');
    assert.match(report.reasons.join(' '), /below the 30 needed/);
  });

  it('says EDGE_SUPPORTED only when the interval excludes zero and the later days hold up', () => {
    const report = runTimeMachine(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS, [], options);
    assert.equal(report.verdict, 'EDGE_SUPPORTED');
    assert.ok((report.bootstrap?.meanRCi95.low ?? 0) > 0);
    assert.match(formatReport(report), /does not authorise live trading/);
  });

  it('says NO_TRADE when every trade stops out', () => {
    const report = runTimeMachine(dataset(days(80, { '10:00': [10, 10, 6.5, 7] })), CONFIG, NO_COSTS, [], options);
    assert.equal(report.verdict, 'NO_TRADE');
    assert.equal(report.overall.stopFirst.rate, 1);
  });

  it('says NO_TRADE when the newer days lose even though the whole sample wins', () => {
    const winners = days(40, { '10:00': [10, 16.5, 10, 16] });
    const losers = Array.from({ length: 60 }, (_, i) => session(shiftDateKey('2026-12-01', i), { '10:00': [10, 10, 6.5, 7] }));
    const report = runTimeMachine(dataset([...winners, ...losers]), CONFIG, NO_COSTS, [], options);
    assert.equal(report.verdict, 'NO_TRADE');
    assert.match(report.reasons.join(' '), /out-of-sample mean net R/);
  });

  it('says INSUFFICIENT_EVIDENCE when the holdout spans fewer independent sessions than the minimum', () => {
    const report = runTimeMachine(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS, [], { ...options, minHoldoutDays: 50 });
    assert.equal(report.verdict, 'INSUFFICIENT_EVIDENCE');
    assert.match(report.reasons.join(' '), /independent holdout sessions, below the 50 needed/);
  });

  it('judges the holdout interval alone: a winning discovery period cannot carry a holdout whose interval includes zero', () => {
    // 48 winning sessions, then a 32-session holdout with 17 wins and 15 losses. The whole sample is almost all wins,
    // but the holdout mean is only slightly positive, and its interval reaches zero.
    const discovery = days(48, { '10:00': [10, 16.5, 10, 16] });
    const holdout = Array.from({ length: 32 }, (_, i) =>
      session(shiftDateKey('2026-11-29', i), { '10:00': i < 17 ? [10, 16.5, 10, 16] : [10, 10, 6.5, 7] }),
    );
    const report = runTimeMachine(dataset([...discovery, ...holdout]), CONFIG, NO_COSTS, [], options);
    assert.notEqual(report.verdict, 'EDGE_SUPPORTED');
    assert.ok((report.bootstrap?.meanRCi95.low ?? 1) <= 0, 'the holdout interval includes zero');
    assert.match(report.reasons.join(' '), /holdout 95% interval/);
  });

  it('keeps EDGE_SUPPORTED only while every cost stress also holds, and never upgrades a weaker result', () => {
    const base = runTimeMachine(dataset(days(80, { '10:00': [10, 16.5, 10, 16] })), CONFIG, NO_COSTS, [], options);
    const losing = runTimeMachine(dataset(days(80, { '10:00': [10, 10, 6.5, 7] })), CONFIG, NO_COSTS, [], options);
    assert.equal(base.verdict, 'EDGE_SUPPORTED');
    assert.equal(applyCostStress(base, [{ label: 'half-spread 1%', report: base }]).verdict, 'EDGE_SUPPORTED');
    const broke = applyCostStress(base, [{ label: 'stop slippage 2x', report: losing }]);
    assert.equal(broke.verdict, 'NO_TRADE');
    assert.match(broke.reasons.join(' '), /fails cost stress "stop slippage 2x": NO_TRADE/);
    assert.equal(applyCostStress(losing, [{ label: 'half-spread 1%', report: base }]).verdict, 'NO_TRADE', 'a stress never upgrades a result');
  });

  it('refuses to judge when too many trades lose their premium series', () => {
    const report = runTimeMachine(dataset(days(50, { '10:00': null })), CONFIG, NO_COSTS, [], options);
    assert.equal(report.verdict, 'INSUFFICIENT_EVIDENCE');
    assert.equal(report.dataGapTrades, 50);
  });
});

describe('replay: implied volatility at entry (research only)', () => {
  /** The standard session with an implied volatility on every option bar. `undefined` leaves the bars without one. */
  function sessionWithIv(date: string, iv: number | undefined): ResearchSession {
    const tag = (bars: readonly Candle[]) => bars.map((bar) => ({ ...bar, ...(iv === undefined ? {} : { iv }) }));
    const base = session(date);
    return {
      ...base,
      calls: Object.fromEntries(Object.entries(base.calls).map(([strike, bars]) => [strike, tag(bars)])),
      puts: Object.fromEntries(Object.entries(base.puts).map(([strike, bars]) => [strike, tag(bars)])),
    };
  }
  const sessionsAt = (count: number, iv: (index: number) => number | undefined) =>
    Array.from({ length: count }, (_, index) => sessionWithIv(shiftDateKey(DAY, index), iv(index)));
  const bucketsOf = (trades: readonly { readonly date: string; readonly context: { readonly ivBucket: string } }[]) =>
    new Map(trades.map((trade) => [trade.date, trade.context.ivBucket]));
  const cellOptions = { iterations: 100, seed: 19, minTrades: 1, splitFraction: 0.6, priorRuns: 0, minHoldoutDays: 1 };

  it('buckets each entry against the ATM IV of the prior sessions at the same minute, and needs ten of them', () => {
    const buckets = bucketsOf(replayDataset(dataset(sessionsAt(13, (index) => 10 + index)), CONFIG, NO_COSTS).trades);
    for (let index = 0; index < 10; index += 1) {
      assert.equal(buckets.get(shiftDateKey(DAY, index)), 'UNKNOWN', `${index} prior session(s) is below the minimum`);
    }
    for (let index = 10; index < 13; index += 1) {
      assert.equal(buckets.get(shiftDateKey(DAY, index)), 'HIGH', 'an IV above every prior session');
    }
  });

  it('puts an IV below its history in the LOW bucket', () => {
    const buckets = bucketsOf(replayDataset(dataset(sessionsAt(13, (index) => 30 - index)), CONFIG, NO_COSTS).trades);
    assert.equal(buckets.get(shiftDateKey(DAY, 12)), 'LOW');
  });

  it('never reads a later session: a spike on a future day leaves an earlier entry unchanged', () => {
    const quiet = bucketsOf(replayDataset(dataset(sessionsAt(13, (index) => (index === 12 ? 10 : 10 + index))), CONFIG, NO_COSTS).trades);
    const spiked = bucketsOf(replayDataset(dataset(sessionsAt(13, (index) => (index === 12 ? 999 : 10 + index))), CONFIG, NO_COSTS).trades);
    assert.equal(spiked.get(shiftDateKey(DAY, 10)), quiet.get(shiftDateKey(DAY, 10)), 'day 10 uses only days 0 to 9');
    assert.notEqual(spiked.get(shiftDateKey(DAY, 12)), quiet.get(shiftDateKey(DAY, 12)), "the entry's own IV still counts");
  });

  it('is metadata only: the same trades with and without implied volatility on the bars', () => {
    const withIv = replayDataset(dataset(sessionsAt(13, (index) => 10 + index)), CONFIG, NO_COSTS).trades;
    const withoutIv = replayDataset(dataset(sessionsAt(13, () => undefined)), CONFIG, NO_COSTS).trades;
    const withoutContext = (trades: readonly { readonly context: unknown }[]) => trades.map((trade) => JSON.stringify({ ...trade, context: null }));
    assert.deepEqual(withoutContext(withIv), withoutContext(withoutIv));
    assert.ok(withoutIv.every((trade) => trade.context.ivBucket === 'UNKNOWN'));
  });

  it('splits cells by the IV bucket only when asked', () => {
    const trades = replayDataset(dataset(sessionsAt(13, (index) => 10 + index)), CONFIG, NO_COSTS).trades;
    const dates = trades.map((trade) => trade.date);
    const off = contextCells({ trades, dates }, new Map(), cellOptions);
    const on = contextCells({ trades, dates }, new Map(), { ...cellOptions, includeIv: true });
    assert.ok(!off.cells.some((cell) => cell.key.includes('ivBucket=')));
    assert.ok(on.cells.some((cell) => cell.key.includes('ivBucket=HIGH')));
  });
});


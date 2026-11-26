import { istParts } from '../time/ist.js';

/** Below this many trades a group's figures are noise. The report still shows them, flagged. */
export const MIN_TRADES_TO_JUDGE = 30;

export const DIMENSIONS = ['strategy', 'posture', 'underlying', 'optionType', 'exitReason', 'entryHour', 'daysToExpiry', 'day'] as const;
export type Dimension = (typeof DIMENSIONS)[number];

/** One closed trade joined to the context journalled when it was entered. */
export interface TradeRecord {
  readonly positionId: string;
  /** False when no entry line was found, so the setup labels are unknown. */
  readonly entryFound: boolean;
  readonly netPnlInr: number;
  readonly chargesInr: number;
  /** Planned loss at the stop. Undefined when the entry line is missing, so R cannot be measured. */
  readonly riskInr: number | undefined;
  readonly labels: Readonly<Record<Dimension, string>>;
}

export interface GroupStats {
  readonly trades: number;
  readonly wins: number;
  readonly losses: number;
  readonly winRatePct: number;
  readonly netPnlInr: number;
  readonly chargesInr: number;
  /** Average net P&L per trade: what one more trade of this kind is expected to make. */
  readonly expectancyInr: number;
  readonly avgWinInr: number | undefined;
  readonly avgLossInr: number | undefined;
  /** Gross wins over gross losses. Undefined with no losing trade. */
  readonly profitFactor: number | undefined;
  /** Average net P&L in units of planned risk. Over trades whose entry line was found. */
  readonly avgR: number | undefined;
  readonly tooFewToJudge: boolean;
}

export interface Funnel {
  readonly signals: number;
  readonly dropped: Readonly<Record<string, number>>;
  readonly submitted: number;
  readonly filled: number;
  readonly rejected: number;
  readonly closed: number;
}

export interface PerformanceReport {
  readonly malformed: number;
  readonly funnel: Funnel;
  readonly overall: GroupStats;
  readonly by: Readonly<Record<Dimension, Readonly<Record<string, GroupStats>>>>;
  /** Closes with no entry line in the journals read, typically trades entered before the first day read. */
  readonly closesWithoutEntry: number;
}

type JournalEvent = Record<string, unknown>;

function text(value: unknown): string | undefined {
  return typeof value === 'string' && value !== '' ? value : undefined;
}

function finite(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

/** Parses every line. Unparseable lines are counted, never skipped silently. */
function parseLines(lines: readonly string[]): { events: JournalEvent[]; malformed: number } {
  const events: JournalEvent[] = [];
  let malformed = 0;
  for (const line of lines) {
    if (line.trim() === '') {
      continue;
    }
    try {
      events.push(JSON.parse(line) as JournalEvent);
    } catch {
      malformed += 1;
    }
  }
  return { events, malformed };
}

function bump(counts: Record<string, number>, key: string): void {
  counts[key] = (counts[key] ?? 0) + 1;
}

function funnelOf(events: readonly JournalEvent[]): Funnel {
  const dropped: Record<string, number> = {};
  const count = (type: string): number => events.filter((event) => event['type'] === type).length;
  for (const event of events) {
    if (event['type'] === 'signal_dropped') {
      bump(dropped, text(event['code']) ?? 'UNKNOWN');
    }
  }
  return {
    signals: count('signal_detected'),
    dropped,
    submitted: count('entry_submitted'),
    filled: count('entry_filled'),
    rejected: count('entry_rejected'),
    closed: count('trade_closed'),
  };
}

function daysToExpiryBucket(days: number | undefined): string {
  if (days === undefined) {
    return 'unknown';
  }
  if (days <= 1) {
    return `${days}`;
  }
  return days <= 3 ? '2-3' : '4+';
}

/** Hour of the entry in IST, from the journalled minute, or else from the entry line's timestamp. */
function entryHour(entry: JournalEvent | undefined): string {
  const minute = finite(entry?.['minuteOfDayIst']) ?? timestampMinute(entry);
  return minute === undefined ? 'unknown' : `${String(Math.floor(minute / 60)).padStart(2, '0')}:00`;
}

function timestampMinute(event: JournalEvent | undefined): number | undefined {
  const at = Date.parse(text(event?.['ts']) ?? '');
  return Number.isNaN(at) ? undefined : istParts(at).minuteOfDay;
}

/** Old journals carry no option type; the contract name says CALL or PUT. */
function optionTypeOf(close: JournalEvent, entry: JournalEvent | undefined): string {
  const explicit = text(close['optionType']) ?? text(entry?.['optionType']);
  if (explicit !== undefined) {
    return explicit;
  }
  const contract = text(close['contract']) ?? '';
  return contract.includes('CALL') ? 'CE' : contract.includes('PUT') ? 'PE' : 'unknown';
}

function labelsOf(close: JournalEvent, entry: JournalEvent | undefined): Record<Dimension, string> {
  const at = Date.parse(text(close['ts']) ?? '');
  return {
    strategy: text(entry?.['strategy']) ?? 'unknown',
    posture: text(entry?.['posture']) ?? 'unknown',
    underlying: text(close['underlying']) ?? 'unknown',
    optionType: optionTypeOf(close, entry),
    exitReason: text(close['reason']) ?? 'unknown',
    entryHour: entryHour(entry),
    daysToExpiry: daysToExpiryBucket(finite(entry?.['daysToExpiry'])),
    day: Number.isNaN(at) ? 'unknown' : istParts(at).date,
  };
}

function plannedRisk(entry: JournalEvent | undefined): number | undefined {
  const quantity = finite(entry?.['quantity']);
  const entryReference = finite(entry?.['entryReference']);
  const stop = finite(entry?.['stopLossPrice']);
  if (quantity === undefined || entryReference === undefined || stop === undefined) {
    return undefined;
  }
  const risk = quantity * (entryReference - stop);
  return risk > 0 ? risk : undefined;
}

/** Joins each close to its entry by correlation id: a position's id is its entry's correlation id. */
export function tradesOf(events: readonly JournalEvent[]): TradeRecord[] {
  const entries = new Map<string, JournalEvent>();
  for (const event of events) {
    const id = text(event['correlationId']);
    if (event['type'] === 'entry_submitted' && id !== undefined) {
      entries.set(id, event);
    }
  }
  return events
    .filter((event) => event['type'] === 'trade_closed' && finite(event['pnlInr']) !== undefined)
    .map((close) => {
      const positionId = text(close['positionId']) ?? 'unknown';
      const entry = entries.get(positionId);
      return {
        positionId,
        entryFound: entry !== undefined,
        netPnlInr: finite(close['pnlInr']) ?? 0,
        chargesInr: finite(close['chargesInr']) ?? 0,
        riskInr: plannedRisk(entry),
        labels: labelsOf(close, entry),
      };
    });
}

function average(values: readonly number[]): number | undefined {
  return values.length === 0 ? undefined : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function round(value: number | undefined): number | undefined {
  return value === undefined ? undefined : Number(value.toFixed(2));
}

export function statsOf(trades: readonly TradeRecord[]): GroupStats {
  const wins = trades.filter((trade) => trade.netPnlInr > 0).map((trade) => trade.netPnlInr);
  const losses = trades.filter((trade) => trade.netPnlInr < 0).map((trade) => trade.netPnlInr);
  const grossWin = wins.reduce((sum, value) => sum + value, 0);
  const grossLoss = -losses.reduce((sum, value) => sum + value, 0);
  const netPnlInr = trades.reduce((sum, trade) => sum + trade.netPnlInr, 0);
  const rMultiples = trades.flatMap((trade) => (trade.riskInr === undefined ? [] : [trade.netPnlInr / trade.riskInr]));
  return {
    trades: trades.length,
    wins: wins.length,
    losses: losses.length,
    winRatePct: trades.length === 0 ? 0 : Number(((wins.length / trades.length) * 100).toFixed(1)),
    netPnlInr: Number(netPnlInr.toFixed(2)),
    chargesInr: Number(trades.reduce((sum, trade) => sum + trade.chargesInr, 0).toFixed(2)),
    expectancyInr: trades.length === 0 ? 0 : Number((netPnlInr / trades.length).toFixed(2)),
    avgWinInr: round(average(wins)),
    avgLossInr: round(average(losses)),
    profitFactor: grossLoss > 0 ? Number((grossWin / grossLoss).toFixed(2)) : undefined,
    avgR: round(average(rMultiples)),
    tooFewToJudge: trades.length < MIN_TRADES_TO_JUDGE,
  };
}

function groupBy(trades: readonly TradeRecord[], dimension: Dimension): Record<string, GroupStats> {
  const groups = new Map<string, TradeRecord[]>();
  for (const trade of trades) {
    const key = trade.labels[dimension];
    groups.set(key, [...(groups.get(key) ?? []), trade]);
  }
  const result: Record<string, GroupStats> = {};
  for (const [key, members] of [...groups.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    result[key] = statsOf(members);
  }
  return result;
}

/**
 * Results across any number of journal days, overall and per setup. Pure: lines in, report out. The caller
 * must pass lines of one mode and client only (see `linesInScope`), so paper and live never mix.
 */
export function buildPerformanceReport(lines: readonly string[]): PerformanceReport {
  const { events, malformed } = parseLines(lines);
  const trades = tradesOf(events);
  const by = Object.fromEntries(DIMENSIONS.map((dimension) => [dimension, groupBy(trades, dimension)])) as Record<
    Dimension,
    Record<string, GroupStats>
  >;
  return {
    malformed,
    funnel: funnelOf(events),
    overall: statsOf(trades),
    by,
    closesWithoutEntry: trades.filter((trade) => !trade.entryFound).length,
  };
}

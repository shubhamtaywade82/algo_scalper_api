/**
 * The OTA-311 shadow comparison. Each entry journals its planned risk and its all-in adverse loss, and each close journals
 * its net P&L after charges. Joined by position, they say whether the all-in figure bounds what the trades lost. A trade whose
 * net loss exceeds its all-in figure is an understatement: the stop filled worse than the model, a gap, or a cost it missed.
 */

export interface ShadowEntry {
  readonly positionId: string;
  readonly underlying: string;
  readonly plannedRiskInr: number;
  /** Null for an entry journalled before the all-in figure existed. Such entries are counted but not compared. */
  readonly allInRiskInr: number | null;
  readonly allInWouldReject: boolean;
  readonly policy: string;
}

export interface ShadowPair {
  readonly entry: ShadowEntry;
  /** Net loss after charges, or undefined while the trade is open or never filled. Winners count as zero loss. */
  readonly realizedLossInr: number | undefined;
  readonly exitReason: string | undefined;
}

export interface ShadowSummary {
  readonly entries: number;
  readonly comparable: number;
  readonly closed: number;
  readonly allInWouldRejectCount: number;
  readonly stopOuts: number;
  /** Closed trades whose net loss exceeded their all-in figure. */
  readonly understated: number;
  /** Stop-outs that exceeded their all-in figure: the gap-through-stop cases. */
  readonly gapThroughStops: number;
  readonly largestShortfallInr: number;
  readonly meanShortfallInr: number | null;
  readonly meanPlannedRiskInr: number | null;
  readonly meanAllInRiskInr: number | null;
}

export class ShadowJournalError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShadowJournalError';
  }
}

const mean = (values: readonly number[]): number | null => (values.length === 0 ? null : values.reduce((sum, value) => sum + value, 0) / values.length);

/** Joins the entry and close lines of one journal day. A malformed line is an error, not a skipped trade. */
export function joinShadow(lines: readonly string[]): ShadowPair[] {
  const entries = new Map<string, ShadowEntry>();
  const closes = new Map<string, { readonly pnlInr: number; readonly reason: string }>();
  lines.forEach((text, index) => {
    if (text.trim() === '') {
      return;
    }
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new ShadowJournalError(`journal line ${index + 1} is not valid JSON`);
    }
    if (event['type'] === 'entry_submitted' && typeof event['correlationId'] === 'string' && typeof event['plannedRiskInr'] === 'number') {
      entries.set(event['correlationId'], {
        positionId: event['correlationId'],
        underlying: typeof event['underlying'] === 'string' ? event['underlying'] : 'UNKNOWN',
        plannedRiskInr: event['plannedRiskInr'],
        allInRiskInr: typeof event['allInRiskInr'] === 'number' ? event['allInRiskInr'] : null,
        allInWouldReject: event['allInWouldReject'] === true,
        policy: typeof event['riskPolicy'] === 'string' ? event['riskPolicy'] : 'off',
      });
    } else if (event['type'] === 'trade_closed' && typeof event['positionId'] === 'string' && typeof event['pnlInr'] === 'number') {
      closes.set(event['positionId'], { pnlInr: event['pnlInr'], reason: typeof event['reason'] === 'string' ? event['reason'] : 'UNKNOWN' });
    }
  });
  return [...entries.values()].map((entry) => {
    const close = closes.get(entry.positionId);
    return {
      entry,
      realizedLossInr: close === undefined ? undefined : Math.max(0, -close.pnlInr),
      exitReason: close?.reason,
    };
  });
}

export function summarizeShadow(pairs: readonly ShadowPair[]): ShadowSummary {
  const closed = pairs.filter((pair) => pair.realizedLossInr !== undefined);
  const comparable = closed.filter((pair) => pair.entry.allInRiskInr !== null);
  const shortfalls = comparable
    .map((pair) => ({ pair, shortfall: (pair.realizedLossInr ?? 0) - (pair.entry.allInRiskInr ?? 0) }))
    .filter(({ shortfall }) => shortfall > 0);
  const stopOuts = closed.filter((pair) => pair.exitReason === 'STOP_LOSS');
  return {
    entries: pairs.length,
    comparable: comparable.length,
    closed: closed.length,
    allInWouldRejectCount: pairs.filter((pair) => pair.entry.allInWouldReject).length,
    stopOuts: stopOuts.length,
    understated: shortfalls.length,
    gapThroughStops: shortfalls.filter(({ pair }) => pair.exitReason === 'STOP_LOSS').length,
    largestShortfallInr: shortfalls.reduce((largest, { shortfall }) => Math.max(largest, shortfall), 0),
    meanShortfallInr: mean(shortfalls.map(({ shortfall }) => shortfall)),
    meanPlannedRiskInr: mean(pairs.map((pair) => pair.entry.plannedRiskInr)),
    meanAllInRiskInr: mean(pairs.flatMap((pair) => (pair.entry.allInRiskInr === null ? [] : [pair.entry.allInRiskInr]))),
  };
}

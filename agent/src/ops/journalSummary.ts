export interface JournalSummary {
  readonly lines: number;
  readonly malformed: number;
  readonly entriesSubmitted: number;
  readonly entriesFilled: number;
  readonly entriesRejected: number;
  readonly closedTrades: number;
  readonly wins: number;
  readonly losses: number;
  readonly realizedPnlInr: number;
  readonly closesByReason: Readonly<Record<string, number>>;
  readonly droppedByCode: Readonly<Record<string, number>>;
  readonly halts: readonly string[];
  readonly killSwitchEvents: readonly string[];
}

type JournalEvent = { type?: unknown; reason?: unknown; code?: unknown; underlying?: unknown; pnlInr?: unknown };

function bump(counts: Record<string, number>, key: string): void {
  counts[key] = (counts[key] ?? 0) + 1;
}

/**
 * Summarises one day's journal for review after a paper or live session. Pure: it
 * reads the lines it is given and never touches the file system. Malformed lines
 * are counted, not skipped silently, so a corrupted journal is visible.
 */
export function summarizeJournal(journalLines: readonly string[]): JournalSummary {
  let malformed = 0;
  let lines = 0;
  let entriesSubmitted = 0;
  let entriesFilled = 0;
  let entriesRejected = 0;
  let closedTrades = 0;
  let wins = 0;
  let losses = 0;
  let realizedPnlInr = 0;
  const closesByReason: Record<string, number> = {};
  const droppedByCode: Record<string, number> = {};
  const halts: string[] = [];
  const killSwitchEvents: string[] = [];

  for (const raw of journalLines) {
    if (raw.trim() === '') {
      continue;
    }
    lines += 1;
    let event: JournalEvent;
    try {
      event = JSON.parse(raw) as JournalEvent;
    } catch {
      malformed += 1;
      continue;
    }
    const underlying = typeof event.underlying === 'string' ? event.underlying : '?';
    switch (event.type) {
      case 'entry_submitted':
        entriesSubmitted += 1;
        break;
      case 'entry_filled':
        entriesFilled += 1;
        break;
      case 'entry_rejected':
        entriesRejected += 1;
        break;
      case 'trade_closed': {
        closedTrades += 1;
        const pnl = typeof event.pnlInr === 'number' ? event.pnlInr : 0;
        realizedPnlInr += pnl;
        if (pnl > 0) {
          wins += 1;
        } else if (pnl < 0) {
          losses += 1;
        }
        bump(closesByReason, typeof event.reason === 'string' ? event.reason : 'UNKNOWN');
        break;
      }
      case 'signal_dropped':
        bump(droppedByCode, typeof event.code === 'string' ? event.code : 'UNKNOWN');
        break;
      case 'halted':
        halts.push(`${underlying}: ${typeof event.reason === 'string' ? event.reason : 'unspecified'}`);
        break;
      case 'book_kill_switch':
      case 'daily_loss_breach':
        killSwitchEvents.push(typeof event.reason === 'string' ? event.reason : event.type);
        break;
      default:
        break;
    }
  }

  return {
    lines,
    malformed,
    entriesSubmitted,
    entriesFilled,
    entriesRejected,
    closedTrades,
    wins,
    losses,
    realizedPnlInr: Number(realizedPnlInr.toFixed(2)),
    closesByReason,
    droppedByCode,
    halts,
    killSwitchEvents,
  };
}

export interface JournalScope {
  readonly mode: string;
  readonly clientId: string;
}

/**
 * Keeps the lines of one mode and client, so paper and live never mix in a report. Untagged lines predate tagging:
 * they are counted, not kept. Unparseable lines are kept, so the summary can report them as malformed.
 */
export function linesInScope(lines: readonly string[], scope: JournalScope): { kept: string[]; untagged: number } {
  const kept: string[] = [];
  let untagged = 0;
  for (const line of lines) {
    if (line.trim() === '') {
      continue;
    }
    let event: { mode?: unknown; client?: unknown };
    try {
      event = JSON.parse(line) as typeof event;
    } catch {
      kept.push(line);
      continue;
    }
    if (typeof event.mode !== 'string' || typeof event.client !== 'string') {
      untagged += 1;
    } else if (event.mode === scope.mode && event.client === scope.clientId) {
      kept.push(line);
    }
  }
  return { kept, untagged };
}

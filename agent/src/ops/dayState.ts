import { allInAdverseLossInr, type AdverseCosts } from '../risk/allInLoss.js';
import { DayBook } from '../risk/dayBook.js';
import { istParts } from '../time/ist.js';

export interface RestoreResult {
  readonly eventsApplied: number;
  /**
   * Underlyings whose last entry has no journalled outcome. They are released so they are not blocked forever, and
   * the planned loss of that entry is booked (see `bookUnresolved`).
   */
  readonly releasedUnresolved: readonly string[];
}

/** The fields of an entry_submitted line that size its loss. Read as journalled: they are validated only when a loss must be booked. */
interface IntentFields {
  readonly quantity: unknown;
  readonly entryReference: unknown;
  readonly stopLossPrice: unknown;
  readonly exchangeSegment: unknown;
  readonly tickSize: unknown;
}

/** An entry_submitted line whose outcome is not (yet) in the journal. */
interface PendingIntent {
  readonly at: number;
  readonly line: number;
  readonly fields: IntentFields;
}

/** Fallback when an older journal line carries no segment. Matches `roundTripChargesInr`'s own default, which is the higher rate. */
const DEFAULT_SEGMENT = 'NSE_FNO';

function isPositiveFinite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

/**
 * Books an entry whose outcome the journal never recorded at its all-in adverse loss: the planned stop distance, plus the
 * stop slippage the costs allow, plus the round-trip charges. The journal cannot tell a rejected entry from a fill that the
 * bracket closed during the outage, and booking zero would hide the second case from the daily-loss counter. The worst case
 * over-counts the first by one trade's loss, which fails toward more protection.
 *
 * Throws when the line has no usable stop or tick, since there is then no loss to book and the day cannot be counted honestly.
 */
function bookUnresolved(book: DayBook, underlying: string, intent: PendingIntent, costs: AdverseCosts): void {
  const { quantity, entryReference, stopLossPrice, exchangeSegment, tickSize } = intent.fields;
  if (
    !isPositiveFinite(quantity) ||
    !isPositiveFinite(entryReference) ||
    !isPositiveFinite(stopLossPrice) ||
    !(entryReference > stopLossPrice) ||
    !isPositiveFinite(tickSize)
  ) {
    throw new Error(`event journal line ${intent.line} records an unresolved ${underlying} entry without a usable stop or tick; inspect it before restarting`);
  }
  const lossInr = allInAdverseLossInr({
    quantity,
    entryPrice: entryReference,
    stopPrice: stopLossPrice,
    costs,
    tickSize,
    exchangeSegment: typeof exchangeSegment === 'string' ? exchangeSegment : DEFAULT_SEGMENT,
  });
  book.recordClose({ underlying, pnlInr: -lossInr, closedAtMs: intent.at });
}

/**
 * Rebuilds today's day-book state (P&L, trade count, cooldowns, breach state)
 * from the append-only journal. Without this, a restart would reset the daily
 * loss counter to zero and allow trading past the limit.
 *
 * Fail-closed: a malformed journal line for the current IST day throws, because
 * skipping it could under-count losses. A truncated final line from an
 * interrupted write is the usual cause, and the operator must inspect it first.
 * An unresolved entry without a usable stop also throws, since it has no loss to book.
 */
export function restoreDayBook(book: DayBook, journalLines: readonly string[], dayKey: string, costs: AdverseCosts): RestoreResult {
  const open = new Map<string, PendingIntent>();
  let applied = 0;
  journalLines.forEach((line, index) => {
    if (line.trim() === '') {
      return;
    }
    let event: {
      ts?: unknown;
      type?: unknown;
      underlying?: unknown;
      pnlInr?: unknown;
      reason?: unknown;
      baselineInr?: unknown;
      enabled?: unknown;
      quantity?: unknown;
      entryReference?: unknown;
      stopLossPrice?: unknown;
      exchangeSegment?: unknown;
      tickSize?: unknown;
    };
    try {
      event = JSON.parse(line) as typeof event;
    } catch {
      throw new Error(`event journal line ${index + 1} is malformed; inspect it before restarting`);
    }
    if (typeof event.ts !== 'string') {
      return;
    }
    const at = Date.parse(event.ts);
    if (Number.isNaN(at) || istParts(at).date !== dayKey) {
      return;
    }
    const underlying = typeof event.underlying === 'string' ? event.underlying : undefined;
    switch (event.type) {
      case 'entry_submitted':
        if (underlying !== undefined) {
          // A new entry for this underlying can only follow an earlier one that the broker has shown settled. That
          // earlier intent has no journalled outcome, so it is booked now rather than overwritten.
          const superseded = open.get(underlying);
          if (superseded !== undefined) {
            bookUnresolved(book, underlying, superseded, costs);
          }
          book.recordEntry(underlying);
          open.set(underlying, {
            at,
            line: index + 1,
            fields: {
              quantity: event.quantity,
              entryReference: event.entryReference,
              stopLossPrice: event.stopLossPrice,
              exchangeSegment: event.exchangeSegment,
              tickSize: event.tickSize,
            },
          });
          applied += 1;
        }
        break;
      case 'entry_rejected':
        if (underlying !== undefined) {
          book.releaseUnfilled(underlying);
          open.delete(underlying);
          applied += 1;
        }
        break;
      case 'trade_closed':
        if (underlying !== undefined && typeof event.pnlInr === 'number') {
          book.recordClose({ underlying, pnlInr: event.pnlInr, closedAtMs: at });
          open.delete(underlying);
          applied += 1;
        }
        break;
      case 'book_kill_switch':
        book.activateKillSwitch(typeof event.reason === 'string' ? event.reason : 'restored breach');
        applied += 1;
        break;
      case 'daily_loss_breach':
        book.recordDailyLossBreach('daily loss limit breached earlier today');
        applied += 1;
        break;
      case 'daily_loss_reset':
        if (typeof event.baselineInr === 'number') {
          book.setDrawdownBaseline(event.baselineInr);
          book.clearKillSwitch();
          applied += 1;
        }
        break;
      case 'daily_loss_brake_toggled':
        if (typeof event.enabled === 'boolean') {
          book.setDailyLossBrake(event.enabled);
          applied += 1;
        }
        break;
      // Replayed in journal order, so a clear that followed a breach clears it here too, as it did at runtime.
      case 'operator_entry_block':
        book.activateKillSwitch(typeof event.reason === 'string' ? event.reason : 'operator entry block (restored)');
        applied += 1;
        break;
      case 'operator_entry_clear':
        book.clearKillSwitch();
        applied += 1;
        break;
      default:
        break;
    }
  });
  const released = [...open.keys()].sort();
  for (const underlying of released) {
    const intent = open.get(underlying);
    if (intent !== undefined) {
      bookUnresolved(book, underlying, intent, costs);
    }
  }
  return { eventsApplied: applied, releasedUnresolved: released };
}

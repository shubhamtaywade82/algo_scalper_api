import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { roundTripChargesInr } from '../src/options/pricing.js';
import { allInAdverseLossInr } from '../src/risk/allInLoss.js';
import { restoreDayBook as restoreWithCosts } from '../src/ops/dayState.js';
import { DayBook } from '../src/risk/dayBook.js';
import type { RestoreResult } from '../src/ops/dayState.js';
import { SESSION_DAY } from './support/fixtures.js';

const line = (ts: string, type: string, extra: Record<string, unknown> = {}): string =>
  JSON.stringify({ ts, type, ...extra });

const T = (hhmm: string, date = SESSION_DAY): string => `${date}T${hhmm}:00+05:30`;

/** Charges only, with the stop filling at its level. Tests that need adverse costs pass them explicitly. */
const ZERO_COSTS = { halfSpreadPct: 0, stopSlippagePct: 0 };
const restoreDayBook = (book: DayBook, journal: readonly string[], dayKey: string, costs = ZERO_COSTS): RestoreResult =>
  restoreWithCosts(book, journal, dayKey, costs);

/** The fields the runtime journals with every entry_submitted line. An unresolved intent is booked at its stop. */
const INTENT = { quantity: 75, entryReference: 100, stopLossPrice: 70, tickSize: 0.05 };
/** Planned loss for INTENT: 75 × (100 − 70) at the stop, plus the estimated round-trip charges on that exit. */
const INTENT_LOSS_INR = Number((-(75 * (100 - 70) + roundTripChargesInr({ quantity: 75, buyPrice: 100, sellPrice: 70, exchangeSegment: 'NSE_FNO' }))).toFixed(2));

describe('restoreDayBook', () => {
  it('rebuilds today\'s P&L, trade count and cooldown after a restart', () => {
    const book = new DayBook(Date.parse(T('09:20')), 300_000);
    const journal = [
      line(T('09:45'), 'entry_submitted', { underlying: 'NIFTY' }),
      line(T('10:10'), 'trade_closed', { underlying: 'NIFTY', pnlInr: -1200 }),
      line(T('10:30'), 'entry_submitted', { underlying: 'NIFTY' }),
      line(T('11:00'), 'trade_closed', { underlying: 'NIFTY', pnlInr: 800 }),
    ];
    const result = restoreDayBook(book, journal, SESSION_DAY);
    const snapshot = book.snapshot();
    assert.equal(result.eventsApplied, 4);
    assert.equal(snapshot.realizedPnlInr, -400);
    assert.equal(snapshot.tradesToday, 2);
    assert.deepEqual(snapshot.openUnderlyings, []);
    assert.equal(book.cooldownUntilFor('NIFTY'), Date.parse(T('11:00')) + 300_000);
  });

  it('restores a daily-loss breach so a restart cannot trade past the limit', () => {
    const book = new DayBook(Date.parse(T('12:00')), 0);
    restoreDayBook(book, [line(T('12:00'), 'daily_loss_breach', { dayPnlInr: -6000 })], SESSION_DAY);
    assert.match(book.snapshot().killSwitchReason ?? '', /daily loss/);
  });

  it('ignores journal lines from other IST days', () => {
    const book = new DayBook(Date.parse(T('09:20')), 0);
    const journal = [
      line(T('15:00', '2026-10-09'), 'trade_closed', { underlying: 'NIFTY', pnlInr: -9999 }),
      line(T('15:00', '2026-10-09'), 'daily_loss_breach', { dayPnlInr: -9999 }),
    ];
    restoreDayBook(book, journal, SESSION_DAY);
    assert.equal(book.snapshot().realizedPnlInr, 0);
    assert.equal(book.snapshot().killSwitchReason, undefined);
  });

  it('releases an entry that was journalled but never resolved, so it does not block the underlying', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    const result = restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'BANKNIFTY', ...INTENT })], SESSION_DAY);
    assert.deepEqual(result.releasedUnresolved, ['BANKNIFTY']);
    assert.deepEqual(book.snapshot().openUnderlyings, []);
    assert.equal(book.snapshot().tradesToday, 1, 'the attempt still counts toward the trade limit');
  });

  it('fails closed on a malformed line rather than under-counting losses', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    assert.throws(
      () => restoreDayBook(book, [line(T('10:00'), 'trade_closed', { underlying: 'NIFTY', pnlInr: -10 }), '{"ts":"2026-10-12T1'], SESSION_DAY),
      /malformed/,
    );
  });

  it('treats blank lines as no-ops', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    assert.equal(restoreDayBook(book, ['', '   '], SESSION_DAY).eventsApplied, 0);
  });
});

describe('restoreDayBook operator actions', () => {
  it('restores an operator entry block after a restart, and a journalled clear lifts it', () => {
    const blockedBook = new DayBook(Date.parse(T('10:00')), 0);
    restoreDayBook(blockedBook, [line(T('10:20'), 'operator_entry_block', { reason: 'operator entry block (10:20)' })], SESSION_DAY);
    assert.equal(blockedBook.snapshot().killSwitchReason, 'operator entry block (10:20)');

    const clearedBook = new DayBook(Date.parse(T('10:00')), 0);
    restoreDayBook(
      clearedBook,
      [line(T('10:20'), 'operator_entry_block', { reason: 'operator entry block (10:20)' }), line(T('10:30'), 'operator_entry_clear')],
      SESSION_DAY,
    );
    assert.equal(clearedBook.snapshot().killSwitchReason, undefined);
  });

  it('restores a daily-loss breach as a latch, and a clear that followed it is replayed in order', () => {
    const breached = new DayBook(Date.parse(T('10:00')), 0);
    restoreDayBook(breached, [line(T('11:00'), 'daily_loss_breach', { dayPnlInr: -2100, limitInr: 2000 })], SESSION_DAY);
    assert.match(breached.snapshot().dailyLossBreach ?? '', /daily loss/);
    assert.match(breached.snapshot().killSwitchReason ?? '', /daily loss/);

    const cleared = new DayBook(Date.parse(T('10:00')), 0);
    restoreDayBook(
      cleared,
      [line(T('11:00'), 'daily_loss_breach', { dayPnlInr: -2100, limitInr: 2000 }), line(T('11:40'), 'operator_entry_clear')],
      SESSION_DAY,
    );
    assert.equal(cleared.snapshot().dailyLossBreach, undefined, 'a clear after the breach must not re-latch on restart');
    assert.equal(cleared.snapshot().killSwitchReason, undefined);
  });

  it('restores a daily-loss reset and brake toggles', () => {
    const book = new DayBook(Date.parse(T('10:00')), 0);
    restoreDayBook(
      book,
      [
        line(T('11:00'), 'trade_closed', { underlying: 'NIFTY', pnlInr: -2500 }),
        line(T('11:05'), 'daily_loss_reset', { baselineInr: -2500 }),
        line(T('11:10'), 'daily_loss_brake_toggled', { enabled: false }),
      ],
      SESSION_DAY,
    );
    const snap = book.snapshot();
    assert.equal(snap.dailyLossBaselineInr, -2500);
    assert.equal(snap.effectiveDayPnlInr, 0);
    assert.equal(snap.dailyLossBrakeEnabled, false);
  });
});

describe('DayBook breach latch', () => {
  it('latches a breach while keeping an operator reason that already holds the kill switch', () => {
    const book = new DayBook(Date.parse(T('10:00')), 0);
    book.activateKillSwitch('operator entry block (10:05)');
    book.recordDailyLossBreach('daily loss -2100.00 breached -2000.00');
    const snapshot = book.snapshot();
    assert.equal(snapshot.killSwitchReason, 'operator entry block (10:05)');
    assert.equal(snapshot.dailyLossBreach, 'daily loss -2100.00 breached -2000.00');
  });
});

describe('restoreDayBook unresolved intents', () => {
  it('starts a cooldown for an intent with no outcome, so a restart cannot re-enter at once', () => {
    const book = new DayBook(Date.parse(T('10:00')), 300_000);
    restoreDayBook(book, [line(T('10:20'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT })], SESSION_DAY);
    assert.deepEqual(book.snapshot().openUnderlyings, [], 'it is released, so it does not block the day forever');
    assert.equal(book.cooldownUntilFor('NIFTY'), Date.parse(T('10:20')) + 300_000);
    assert.equal(book.snapshot().tradesToday, 1, 'the attempt counts toward the trade limit');
  });

  it('books an unresolved intent at its planned stop loss net of charges, never at zero, so a fill closed during the outage still counts', () => {
    // The journal cannot tell a rejected entry from one the bracket closed while the process was down. The
    // worst case is booked: a rejected one over-counts by one trade's planned risk, a closed one is not hidden.
    const book = new DayBook(Date.parse(T('10:30')), 0);
    restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT })], SESSION_DAY);
    assert.equal(book.snapshot().realizedPnlInr, INTENT_LOSS_INR);
    assert.ok(INTENT_LOSS_INR < -2250, 'the booked loss includes the charges, so it is more than the gross stop loss');
  });

  it('books a superseded unresolved intent when the same underlying is entered again, so neither trade is dropped', () => {
    const book = new DayBook(Date.parse(T('11:30')), 0);
    restoreDayBook(
      book,
      [
        line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT }),
        line(T('10:30'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT }),
        line(T('11:00'), 'trade_closed', { underlying: 'NIFTY', pnlInr: 300 }),
      ],
      SESSION_DAY,
    );
    assert.equal(book.snapshot().realizedPnlInr, INTENT_LOSS_INR + 300);
    assert.deepEqual(book.snapshot().openUnderlyings, []);
    assert.equal(book.snapshot().tradesToday, 2);
  });

  it('adds a planned loss to the daily-loss counter exactly as a realised loss would be', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    restoreDayBook(
      book,
      [
        line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT }),
        line(T('10:05'), 'trade_closed', { underlying: 'BANKNIFTY', pnlInr: 500 }),
      ],
      SESSION_DAY,
    );
    assert.equal(book.snapshot().realizedPnlInr, INTENT_LOSS_INR + 500);
  });

  it('fails closed on an unresolved intent without a usable stop, rather than booking it at zero', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    assert.throws(
      () => restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', entryReference: 100 })], SESSION_DAY),
      /without a usable stop/,
    );
  });

  it('refuses an unresolved intent whose stop is at or above its entry, which has no loss to book', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    assert.throws(
      () => restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT, stopLossPrice: 100 })], SESSION_DAY),
      /without a usable stop/,
    );
  });

  it('a resolved intent is not booked twice: an entry_rejected line releases it without a loss', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    restoreDayBook(
      book,
      [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT }), line(T('10:01'), 'entry_rejected', { underlying: 'NIFTY' })],
      SESSION_DAY,
    );
    assert.equal(book.snapshot().realizedPnlInr, 0);
  });
});

describe('restoreDayBook all-in loss (OTA-311)', () => {
  it('books an unresolved intent at its all-in loss, so adverse costs at the stop are not hidden', () => {
    const costs = { halfSpreadPct: 1, stopSlippagePct: 1 };
    const book = new DayBook(Date.parse(T('10:30')), 0);
    restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT })], SESSION_DAY, costs);
    const expected = -allInAdverseLossInr({ quantity: 75, entryPrice: 100, stopPrice: 70, costs, tickSize: 0.05, exchangeSegment: 'NSE_FNO' });
    assert.equal(book.snapshot().realizedPnlInr, expected);
    assert.ok(expected < INTENT_LOSS_INR, 'a stop that fills below its level costs more than the planned distance');
  });

  it('fails closed on an unresolved intent without a tick, since the exit price cannot be rounded to the grid', () => {
    const book = new DayBook(Date.parse(T('10:30')), 0);
    assert.throws(
      () => restoreDayBook(book, [line(T('10:00'), 'entry_submitted', { underlying: 'NIFTY', ...INTENT, tickSize: undefined })], SESSION_DAY),
      /without a usable stop or tick/,
    );
  });
});

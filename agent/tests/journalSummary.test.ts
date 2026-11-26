import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { linesInScope, summarizeJournal } from '../src/ops/journalSummary.js';

const line = (type: string, extra: Record<string, unknown> = {}): string => JSON.stringify({ ts: '2026-10-12T10:00:00.000Z', type, ...extra });

describe('summarizeJournal', () => {
  it('counts entries, wins, losses, realised P&L and exit reasons', () => {
    const summary = summarizeJournal([
      line('entry_submitted', { underlying: 'NIFTY' }),
      line('entry_filled', { underlying: 'NIFTY' }),
      line('trade_closed', { underlying: 'NIFTY', pnlInr: 4545.5, reason: 'TARGET' }),
      line('entry_submitted', { underlying: 'NIFTY' }),
      line('entry_rejected', { underlying: 'NIFTY', reason: 'margin' }),
      line('trade_closed', { underlying: 'NIFTY', pnlInr: -2272.25, reason: 'STOP_LOSS' }),
    ]);
    assert.equal(summary.entriesSubmitted, 2);
    assert.equal(summary.entriesFilled, 1);
    assert.equal(summary.entriesRejected, 1);
    assert.equal(summary.closedTrades, 2);
    assert.equal(summary.wins, 1);
    assert.equal(summary.losses, 1);
    assert.equal(summary.realizedPnlInr, 2273.25);
    assert.deepEqual(summary.closesByReason, { TARGET: 1, STOP_LOSS: 1 });
  });

  it('tallies why signals were dropped and lists halts and kill-switch events', () => {
    const summary = summarizeJournal([
      line('signal_dropped', { code: 'NO_CONTRACT_AT_STRIKE' }),
      line('signal_dropped', { code: 'NO_CONTRACT_AT_STRIKE' }),
      line('signal_dropped', { code: 'ADVISOR_SKIP' }),
      line('halted', { underlying: 'NIFTY', reason: 'entry unconfirmed' }),
      line('book_kill_switch', { reason: 'NIFTY: entry unconfirmed' }),
      line('daily_loss_breach', { dayPnlInr: -3100, limitInr: 3000 }),
    ]);
    assert.deepEqual(summary.droppedByCode, { NO_CONTRACT_AT_STRIKE: 2, ADVISOR_SKIP: 1 });
    assert.deepEqual(summary.halts, ['NIFTY: entry unconfirmed']);
    assert.deepEqual(summary.killSwitchEvents, ['NIFTY: entry unconfirmed', 'daily_loss_breach']);
  });

  it('counts malformed lines rather than hiding them, and ignores blank lines', () => {
    const summary = summarizeJournal(['', line('trade_closed', { pnlInr: 10 }), '{"ts":"2026-10-1', '   ']);
    assert.equal(summary.lines, 2);
    assert.equal(summary.malformed, 1);
    assert.equal(summary.realizedPnlInr, 10);
  });
});

describe('linesInScope', () => {
  it('should keep one mode and client only, count untagged lines, and keep unparseable lines for the malformed count', () => {
    const lines = [
      JSON.stringify({ type: 'a', mode: 'paper', client: '1' }),
      JSON.stringify({ type: 'b', mode: 'live', client: '1' }),
      JSON.stringify({ type: 'c', mode: 'paper', client: '2' }),
      JSON.stringify({ type: 'd' }),
      'not json',
      '',
    ];
    const scoped = linesInScope(lines, { mode: 'paper', clientId: '1' });
    assert.deepEqual(scoped.kept, [lines[0], 'not json']);
    assert.equal(scoped.untagged, 1);
  });
});

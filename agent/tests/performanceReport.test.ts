import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { buildPerformanceReport, MIN_TRADES_TO_JUDGE } from '../src/ops/performanceReport.js';
import { istEpoch } from './support/fixtures.js';

function line(fields: Record<string, unknown>): string {
  return JSON.stringify({ mode: 'paper', client: '1', ...fields });
}

/** One entered and closed trade. Risk is 75 × (100 − 70) = 2250. */
function trade(id: string, pnlInr: number, entry: Record<string, unknown> = {}, close: Record<string, unknown> = {}): string[] {
  return [
    line({
      ts: new Date(istEpoch('2026-10-13', '10:05')).toISOString(),
      type: 'entry_submitted',
      underlying: 'NIFTY',
      correlationId: id,
      contract: 'NIFTY 20 OCT 25000 CALL',
      quantity: 75,
      entryReference: 100,
      stopLossPrice: 70,
      targetPrice: 160,
      strategy: 'range',
      posture: 'aligned',
      optionType: 'CE',
      daysToExpiry: 2,
      minuteOfDayIst: 605,
      ...entry,
    }),
    line({
      ts: new Date(istEpoch('2026-10-13', '10:20')).toISOString(),
      type: 'trade_closed',
      underlying: 'NIFTY',
      positionId: id,
      contract: 'NIFTY 20 OCT 25000 CALL',
      pnlInr,
      chargesInr: 50,
      reason: pnlInr > 0 ? 'TARGET' : 'STOP_LOSS',
      ...close,
    }),
  ];
}

describe('buildPerformanceReport', () => {
  it('should compute expectancy, win rate, profit factor and R from net P&L', () => {
    const report = buildPerformanceReport([...trade('A', 4500), ...trade('B', -2250), ...trade('C', -2250)]);
    const all = report.overall;
    assert.equal(all.trades, 3);
    assert.equal(all.wins, 1);
    assert.equal(all.winRatePct, 33.3);
    assert.equal(all.netPnlInr, 0);
    assert.equal(all.expectancyInr, 0);
    assert.equal(all.avgWinInr, 4500);
    assert.equal(all.avgLossInr, -2250);
    assert.equal(all.profitFactor, 1);
    assert.equal(all.avgR, 0, '(2 − 1 − 1) / 3');
    assert.equal(all.chargesInr, 150);
  });

  it('should group each trade by the setup journalled at its entry', () => {
    const report = buildPerformanceReport([
      ...trade('A', 1000),
      ...trade('B', -500, { strategy: 'trend', posture: 'scout', optionType: 'PE', daysToExpiry: 0, minuteOfDayIst: 800 }),
    ]);
    assert.deepEqual(Object.keys(report.by.strategy), ['range', 'trend']);
    assert.equal(report.by.strategy['trend']?.netPnlInr, -500);
    assert.equal(report.by.posture['scout']?.trades, 1);
    assert.deepEqual(Object.keys(report.by.daysToExpiry), ['0', '2-3']);
    assert.deepEqual(Object.keys(report.by.entryHour), ['10:00', '13:00']);
    assert.deepEqual(Object.keys(report.by.exitReason), ['STOP_LOSS', 'TARGET']);
    assert.deepEqual(Object.keys(report.by.day), ['2026-10-13']);
  });

  it('should label a close with no entry line as unknown, read its option type from the contract, and count it', () => {
    const closeOnly = trade('Z', 300, {}, { contract: 'BANKNIFTY 28 OCT 52000 PUT' })[1] as string;
    const report = buildPerformanceReport([closeOnly]);
    assert.equal(report.closesWithoutEntry, 1);
    assert.equal(report.by.strategy['unknown']?.trades, 1);
    assert.equal(report.by.optionType['PE']?.trades, 1);
    assert.equal(report.overall.avgR, undefined, 'no planned risk, so no R');
    assert.equal(report.by.entryHour['unknown']?.trades, 1);
  });

  it('should flag groups too small to judge, and leave profit factor undefined with no losses', () => {
    const report = buildPerformanceReport(trade('A', 100));
    assert.equal(report.overall.tooFewToJudge, true);
    assert.equal(report.overall.profitFactor, undefined);
    const many = Array.from({ length: MIN_TRADES_TO_JUDGE }, (_, i) => trade(`T${i}`, i % 2 === 0 ? 100 : -50)).flat();
    assert.equal(buildPerformanceReport(many).overall.tooFewToJudge, false);
  });

  it('should count the signal funnel and every drop reason, and count malformed lines', () => {
    const report = buildPerformanceReport([
      line({ type: 'signal_detected' }),
      line({ type: 'signal_detected' }),
      line({ type: 'signal_dropped', code: 'SPREAD_TOO_WIDE' }),
      line({ type: 'entry_rejected' }),
      'not json',
      ...trade('A', 100),
    ]);
    assert.deepEqual(report.funnel, { signals: 2, dropped: { SPREAD_TOO_WIDE: 1 }, submitted: 1, filled: 0, rejected: 1, closed: 1 });
    assert.equal(report.malformed, 1);
  });
});

import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { joinShadow, ShadowJournalError, summarizeShadow } from '../src/risk/riskShadow.js';

/** OTA-311 shadow comparison: does the all-in figure bound what the trades actually lost, including charges, slippage and gaps? */

const entry = (id: string, planned: number, allIn: number | null, wouldReject = false): string =>
  JSON.stringify({ type: 'entry_submitted', correlationId: id, underlying: 'NIFTY', plannedRiskInr: planned, allInRiskInr: allIn, allInWouldReject: wouldReject, riskPolicy: 'shadow' });
const close = (id: string, pnl: number, reason: string): string => JSON.stringify({ type: 'trade_closed', positionId: id, pnlInr: pnl, reason });

describe('shadow comparison (OTA-311)', () => {
  it('joins each entry to its close by position, and leaves an open trade without a loss', () => {
    const pairs = joinShadow([entry('E1', 2250, 2400), close('E1', -2100, 'STOP_LOSS'), entry('E2', 2250, 2400)]);
    assert.equal(pairs.length, 2);
    assert.equal(pairs.find((pair) => pair.entry.positionId === 'E1')?.realizedLossInr, 2100);
    assert.equal(pairs.find((pair) => pair.entry.positionId === 'E2')?.realizedLossInr, undefined);
  });

  it('counts a winner as no loss, so it cannot understate the all-in figure', () => {
    const pairs = joinShadow([entry('E1', 2250, 2400), close('E1', 900, 'TARGET')]);
    assert.equal(pairs[0]?.realizedLossInr, 0);
    assert.equal(summarizeShadow(pairs).understated, 0);
  });

  it('finds no understatement when the net loss, charges included, sits inside the all-in figure', () => {
    const summary = summarizeShadow(joinShadow([entry('E1', 2250, 2400), close('E1', -2400, 'STOP_LOSS')]));
    assert.equal(summary.understated, 0, 'equal to the all-in figure is not an understatement');
    assert.equal(summary.stopOuts, 1);
  });

  it('flags a gap through the stop as an understatement, with its shortfall', () => {
    // Stop filled far below the modelled exit: net loss 2,700 against an all-in figure of 2,400.
    const summary = summarizeShadow(joinShadow([entry('E1', 2250, 2400), close('E1', -2700, 'STOP_LOSS')]));
    assert.equal(summary.understated, 1);
    assert.equal(summary.gapThroughStops, 1);
    assert.equal(summary.largestShortfallInr, 300);
  });

  it('flags a non-stop loss that exceeds the all-in figure too, so a cost the model missed is visible', () => {
    const summary = summarizeShadow(joinShadow([entry('E1', 2250, 2400), close('E1', -2500, 'TIME_STOP')]));
    assert.equal(summary.understated, 1);
    assert.equal(summary.gapThroughStops, 0, 'it is not a stop-out, so it is not counted as a gap');
  });

  it('counts entries journalled before the all-in figure existed, but does not compare them', () => {
    const summary = summarizeShadow(joinShadow([entry('E1', 2250, null), close('E1', -2700, 'STOP_LOSS')]));
    assert.equal(summary.entries, 1);
    assert.equal(summary.comparable, 0);
    assert.equal(summary.understated, 0);
  });

  it('counts the entries the all-in budget would have refused, for the decision to enforce', () => {
    const summary = summarizeShadow(joinShadow([entry('E1', 2250, 2400, true), entry('E2', 2250, 2250, false)]));
    assert.equal(summary.allInWouldRejectCount, 1);
  });

  it('refuses a malformed journal line, naming it, rather than dropping a trade', () => {
    assert.throws(() => joinShadow([entry('E1', 2250, 2400), '{"type":"trade_closed"'] ), (error: unknown) => error instanceof ShadowJournalError && /line 2/.test(error.message));
  });
});

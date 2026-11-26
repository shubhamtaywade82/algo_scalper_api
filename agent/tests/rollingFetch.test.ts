import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { requestBlocks, ROLLING_EXPIRY_CODES, ROLLING_MAX_SPAN_DAYS, rollingRequest } from '../src/research/rollingFetch.js';
import { shiftDateKey } from '../src/time/ist.js';

/** Every session date the blocks request, under Dhan's non-inclusive toDate. */
function requestedDates(blocks: readonly { from: string; to: string }[]): Set<string> {
  const dates = new Set<string>();
  for (const block of blocks) {
    for (let date = block.from; date < block.to; date = shiftDateKey(date, 1)) {
      dates.add(date);
    }
  }
  return dates;
}

function sessionsBetween(fromDate: string, toDate: string): string[] {
  const out: string[] = [];
  for (let date = fromDate; date <= toDate; date = shiftDateKey(date, 1)) {
    out.push(date);
  }
  return out;
}

describe('rolling-option request blocks', () => {
  it('requests every session in the range, including the last one', () => {
    for (const [from, to] of [
      ['2026-10-01', '2026-10-31'],
      ['2026-10-01', '2026-10-30'],
      ['2026-10-01', '2026-10-01'],
      ['2026-10-01', '2026-12-31'],
    ] as const) {
      const requested = requestedDates(requestBlocks(from, to, ROLLING_MAX_SPAN_DAYS));
      for (const session of sessionsBetween(from, to)) {
        assert.ok(requested.has(session), `${session} is in ${from}..${to} but was never requested`);
      }
    }
  });

  it('never asks for more than the span limit in one request', () => {
    for (const block of requestBlocks('2026-10-01', '2026-12-31', ROLLING_MAX_SPAN_DAYS)) {
      const span = (Date.parse(`${block.to}T00:00:00Z`) - Date.parse(`${block.from}T00:00:00Z`)) / 86_400_000;
      assert.ok(span <= ROLLING_MAX_SPAN_DAYS, `${block.from}..${block.to} spans ${span} days`);
    }
  });

  it('requests no day twice', () => {
    const blocks = requestBlocks('2026-10-01', '2026-12-31', ROLLING_MAX_SPAN_DAYS);
    const seen = new Set<string>();
    for (const block of blocks) {
      for (let date = block.from; date < block.to; date = shiftDateKey(date, 1)) {
        assert.ok(!seen.has(date), `${date} is requested twice`);
        seen.add(date);
      }
    }
  });
});

describe('rolling-option request', () => {
  const block = { from: '2026-10-01', to: '2026-10-31' };
  const base = {
    securityId: '13',
    exchangeSegment: 'NSE_FNO' as const,
    expiryFlag: 'WEEK' as const,
    expiryCode: 1 as const,
    strike: 'ATM',
    drvOptionType: 'CALL' as const,
    interval: '5' as const,
    requiredData: ['open', 'close'] as const,
    block,
  };

  it('sends the block as given: the SDK must not move our exclusive end date', () => {
    const request = rollingRequest(base);
    assert.equal(request.fromDate, '2026-10-01');
    assert.equal(request.toDate, '2026-10-31');
    assert.equal(request.autoAdjustDates, false);
    assert.equal(request.instrument, 'OPTIDX');
  });

  it('accepts only the expiry codes the SDK schema accepts', () => {
    assert.deepEqual([...ROLLING_EXPIRY_CODES], [0, 1, 2]);
  });
});

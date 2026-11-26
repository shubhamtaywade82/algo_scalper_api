import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import {
  DEFAULT_MAX_AGE_MS,
  checkSharedChainConfluence,
  createSharedChainContextReader,
  sharedChainAnalysis,
  sharedChainContextKey,
  type ChainContextSnapshot,
} from '../src/options/sharedChainContext.js';

const VALID_CONTEXT: ChainContextSnapshot = {
  schema: 'chain-context/1',
  underlying: 'NIFTY',
  expiry: '2026-11-26',
  spot: 25453.35,
  computed_at_ms: 1_763_766_062_114,
  source: 'algo_scalper_api',
  window_strikes: 5,
  pcr: 1.31,
  atm_pcr: 1.18,
  call_resistance: { strike: 25600, oi: 2541000, distance: 146.7 },
  put_support: { strike: 25300, oi: 1887500, distance: 153.4 },
  headroom_ce: 146.7,
  headroom_pe: 153.4,
  straddle_premium: 231.15,
  expected_range: { lower: 25218.85, upper: 25468.15 },
  sentiment_score: 40,
  bias: 'BULLISH',
  verdict: 'BULLISH (score +40, PCR 1.31, ATM PCR 1.18)',
};

function readerWith(rawFor: (key: string) => string | null, now = () => VALID_CONTEXT.computed_at_ms + 1000) {
  return createSharedChainContextReader({
    redis: { get: async (key: string) => rawFor(key) },
    underlying: 'NIFTY',
    now,
  });
}

describe('sharedChainContextKey', () => {
  it('normalises the underlying into the contract key', () => {
    assert.equal(sharedChainContextKey('nifty'), 'dhan:chain:context:NIFTY');
    assert.equal(sharedChainContextKey('BANKNIFTY'), 'dhan:chain:context:BANKNIFTY');
  });
});

describe('createSharedChainContextReader', () => {
  it('reads and validates a fresh snapshot', async () => {
    const reader = readerWith((key) => (key === 'dhan:chain:context:NIFTY' ? JSON.stringify(VALID_CONTEXT) : null));
    const snapshot = await reader.read();
    assert.ok(snapshot !== undefined);
    assert.equal(snapshot.pcr, 1.31);
    assert.equal(snapshot.call_resistance.strike, 25600);
    assert.equal(snapshot.bias, 'BULLISH');
  });

  it('returns undefined when the key is missing or empty', async () => {
    const reader = readerWith(() => null);
    assert.equal(await reader.read(), undefined);
    const reader2 = readerWith(() => '');
    assert.equal(await reader2.read(), undefined);
  });

  it('returns undefined on a stale snapshot (older than maxAgeMs) or a future-dated one', async () => {
    const stale = readerWith(() => JSON.stringify(VALID_CONTEXT), () => VALID_CONTEXT.computed_at_ms + DEFAULT_MAX_AGE_MS + 1);
    assert.equal(await stale.read(), undefined);
    const future = readerWith(() => JSON.stringify(VALID_CONTEXT), () => VALID_CONTEXT.computed_at_ms - 5_000);
    assert.equal(await future.read(), undefined);
  });

  it('returns undefined on payload that drifts from the contract', async () => {
    const droppedField = { ...VALID_CONTEXT, pcr: undefined };
    const reader = readerWith(() => JSON.stringify(droppedField));
    assert.equal(await reader.read(), undefined);

    const wrongVersion = { ...VALID_CONTEXT, schema: 'chain-context/2' };
    const reader2 = readerWith(() => JSON.stringify(wrongVersion));
    assert.equal(await reader2.read(), undefined);
  });

  it('returns undefined when the payload is not JSON or redis.get rejects', async () => {
    const reader = readerWith(() => 'not json');
    assert.equal(await reader.read(), undefined);
    const broken = createSharedChainContextReader({
      redis: { get: async () => { throw new Error('connection refused'); } },
      underlying: 'NIFTY',
    });
    assert.equal(await broken.read(), undefined);
  });
});

describe('sharedChainAnalysis', () => {
  it('adapts the contract payload to the local gate shape', () => {
    const analysis = sharedChainAnalysis({ ...VALID_CONTEXT });
    assert.equal(analysis.spot, 25453.35);
    assert.equal(analysis.pcr, 1.31);
    assert.equal(analysis.headroomCe, 146.7);
    assert.equal(analysis.callResistance.oi, 2541000);
    assert.equal(analysis.putSupport.strike, 25300);
    assert.equal(analysis.bias, 'BULLISH');
  });
});

describe('checkSharedChainConfluence', () => {
  const analysis = sharedChainAnalysis({ ...VALID_CONTEXT });

  it('blocks a bullish entry with thin headroom under the call wall', () => {
    const thin = { ...analysis, headroomCe: 12.5, spot: 25587.5 };
    const result = checkSharedChainConfluence(thin, 'BULLISH', 15);
    assert.equal(result.ok, false);
    assert.match(result.reason ?? '', /12\.5 pts below major Call resistance/);
  });

  it('blocks a bearish entry with thin headroom under the put wall', () => {
    const thin = { ...analysis, headroomPe: 9.8 };
    const result = checkSharedChainConfluence(thin, 'BEARISH', 15);
    assert.equal(result.ok, false);
    assert.match(result.reason ?? '', /9\.8 pts above major Put support/);
  });

  it('blocks bullish when PCR is severely depressed', () => {
    const depressed = { ...analysis, pcr: 0.51 };
    const result = checkSharedChainConfluence(depressed, 'BULLISH', 15);
    assert.equal(result.ok, false);
    assert.match(result.reason ?? '', /PCR 0\.51 is severely depressed/);
  });

  it('blocks bearish when PCR is extremely elevated', () => {
    const elevated = { ...analysis, pcr: 1.92 };
    const result = checkSharedChainConfluence(elevated, 'BEARISH', 15);
    assert.equal(result.ok, false);
    assert.match(result.reason ?? '', /PCR 1\.92 is extremely elevated/);
  });

  it('accepts a healthy bullish and bearish setup', () => {
    assert.equal(checkSharedChainConfluence(analysis, 'BULLISH', 15).ok, true);
    assert.equal(checkSharedChainConfluence(analysis, 'BEARISH', 15).ok, true);
  });

  it('does not block a breached wall (headroom <= 0)', () => {
    const breached = { ...analysis, headroomCe: -47.2 };
    const result = checkSharedChainConfluence(breached, 'BULLISH', 15);
    assert.equal(result.ok, true);
  });
});

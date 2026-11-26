import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import {
  appendRecord,
  assertCanAppend,
  bodyFromRunLine,
  canonicalJson,
  costsFingerprint,
  GENESIS_HASH,
  LedgerIntegrityError,
  LedgerRuleError,
  overlapGroupFor,
  parseLedger,
  priorVariantCount,
  seal,
  verifyLedger,
  type LedgerBody,
  type LedgerRecord,
} from '../src/research/experimentLedger.js';

/** The research ledger is the divisor for every multiple-testing claim. These tests protect what it counts and how it chains. */

const PROVENANCE = { sdk_version: '2.0.1', parser_version: 'rollingoption-v1', response_schema_version: 'rollingoption-layout-1' };

function body(overrides: Partial<LedgerBody> = {}): LedgerBody {
  return {
    record_kind: 'experiment',
    hypothesis_id: null,
    strategy_id: 'trend',
    parameter_fingerprint: 'p1',
    dataset_hash: 'd1',
    underlying: 'NIFTY',
    date_range: { from: '2025-07-01', to: '2025-12-31', label: null },
    overlap_group: 'G1',
    experiment_type: 'discovery',
    holdout_status: 'NotHoldout',
    cells: 60,
    variants_evaluated: 1,
    costs_fingerprint: 'c1',
    provenance: PROVENANCE,
    result: { verdict: 'NO_TRADE' },
    source: 'test',
    created_at: '2026-11-03T10:00:00Z',
    ...overrides,
  };
}

function chain(...bodies: LedgerBody[]): LedgerRecord[] {
  return bodies.reduce<LedgerRecord[]>((records, next) => appendRecord(records, next).records, []);
}

describe('canonical hashing', () => {
  it('produces the same bytes for the same value whatever the key order, and ignores undefined fields', () => {
    assert.equal(canonicalJson({ b: 1, a: { d: 2, c: 3 } }), canonicalJson({ a: { c: 3, d: 2 }, b: 1 }));
    assert.equal(canonicalJson({ a: 1, b: undefined }), canonicalJson({ a: 1 }));
  });

  it('gives different costs different fingerprints, so two cost models cannot be confused', () => {
    assert.notEqual(costsFingerprint({ halfSpreadPct: 0.25, stopSlippagePct: 0.25 }), costsFingerprint({ halfSpreadPct: 1, stopSlippagePct: 1 }));
  });
});

describe('the hash chain', () => {
  it('seals each record onto the one before it, starting from GENESIS', () => {
    const records = chain(body(), body({ dataset_hash: 'd2' }));
    assert.equal(records[0]?.prev_hash, GENESIS_HASH);
    assert.equal(records[1]?.prev_hash, records[0]?.entry_hash);
    assert.equal(records[1]?.seq, 2);
    verifyLedger(records);
  });

  it('refuses a record whose body was changed after it was sealed', () => {
    const records = chain(body(), body({ dataset_hash: 'd2' }));
    const tampered = [records[0], { ...records[1], result: { verdict: 'EDGE_SUPPORTED' } }] as LedgerRecord[];
    assert.throws(() => verifyLedger(tampered), (error: unknown) => error instanceof LedgerIntegrityError && /changed after it was sealed/.test(error.message));
  });

  it('refuses a ledger with a record removed, and one whose records are reordered', () => {
    const records = chain(body(), body({ dataset_hash: 'd2' }), body({ dataset_hash: 'd3' }));
    assert.throws(() => verifyLedger([records[0], records[2]] as LedgerRecord[]), LedgerIntegrityError);
    assert.throws(() => verifyLedger([records[1], records[0], records[2]] as LedgerRecord[]), LedgerIntegrityError);
  });

  it('reads a malformed line as an integrity failure, naming the line', () => {
    const text = `${JSON.stringify(chain(body())[0])}\n{"seq":`;
    assert.throws(() => parseLedger(text), /ledger line 2 is not valid JSON/);
  });
});

describe('variant counting (the divisor)', () => {
  it('counts every variant, and a new dataset hash does not reset the count', () => {
    const records = chain(body({ dataset_hash: 'old' }), body({ dataset_hash: 'new', variants_evaluated: 2 }));
    assert.equal(priorVariantCount(records), 3);
  });

  it('never counts a registration as an evaluated variant', () => {
    const records = chain(body({ record_kind: 'registration', hypothesis_id: 'H1', variants_evaluated: 1, experiment_type: 'discovery' }), body());
    assert.equal(priorVariantCount(records), 1);
  });
});

describe('overlap groups', () => {
  it('puts overlapping date ranges on the same underlying in one group, so overlapping evidence stays linked', () => {
    const records = chain(body({ overlap_group: 'G1', date_range: { from: '2025-10-01', to: '2026-09-30', label: null } }));
    assert.equal(overlapGroupFor(records, 'NIFTY', { from: '2026-04-01', to: '2026-09-30', label: null }), 'G1');
  });

  it('opens a new group for disjoint ranges, and never mixes underlyings', () => {
    const records = chain(body({ overlap_group: 'G1', date_range: { from: '2025-01-01', to: '2025-06-30', label: null } }));
    assert.equal(overlapGroupFor(records, 'NIFTY', { from: '2026-01-01', to: '2026-06-30', label: null }), 'G2');
    assert.equal(overlapGroupFor(records, 'SENSEX', { from: '2025-01-01', to: '2025-06-30', label: null }), 'G2');
  });

  it('matches an unknown date range only by its label', () => {
    const records = chain(body({ overlap_group: 'G1', date_range: { from: null, to: null, label: 'NIFTY 2026H' } }));
    assert.equal(overlapGroupFor(records, 'NIFTY', { from: null, to: null, label: 'NIFTY 2026H' }), 'G1');
    assert.equal(overlapGroupFor(records, 'NIFTY', { from: null, to: null, label: 'NIFTY 2025H' }), 'G2');
  });
});

describe('the rules for appending (pre-registration and holdout status)', () => {
  it('refuses a confirmation that was not registered first', () => {
    assert.throws(() => assertCanAppend([], body({ experiment_type: 'confirmation', holdout_status: 'Frozen', hypothesis_id: 'H1' })), LedgerRuleError);
  });

  it('refuses a confirmation on a window that is not Frozen', () => {
    const records = chain(body({ record_kind: 'registration', hypothesis_id: 'H1', experiment_type: 'discovery' }));
    assert.throws(
      () => assertCanAppend(records, body({ experiment_type: 'confirmation', holdout_status: 'Spent', hypothesis_id: 'H1' })),
      /needs a Frozen window/,
    );
  });

  it('accepts a confirmation on a Frozen window after its registration', () => {
    const records = chain(body({ record_kind: 'registration', hypothesis_id: 'H1', experiment_type: 'discovery' }));
    assert.doesNotThrow(() => assertCanAppend(records, body({ experiment_type: 'confirmation', holdout_status: 'Frozen', hypothesis_id: 'H1' })));
  });

  it('refuses a second registration of the same hypothesis', () => {
    const records = chain(body({ record_kind: 'registration', hypothesis_id: 'H1', experiment_type: 'discovery' }));
    assert.throws(() => assertCanAppend(records, body({ record_kind: 'registration', hypothesis_id: 'H1' })), /already registered/);
  });

  it('keeps a Spent window as documented evidence, as a backfill, and never as a fresh confirmation', () => {
    const preserved = body({ record_kind: 'backfill', experiment_type: 'confirmation', holdout_status: 'Spent', cells: 2, variants_evaluated: 1 });
    assert.doesNotThrow(() => assertCanAppend([], preserved));
    assert.throws(() => assertCanAppend([], body({ experiment_type: 'confirmation', holdout_status: 'Spent', hypothesis_id: 'H1' })), LedgerRuleError);
  });

  it('refuses a run that evaluated no variant, and a negative cell count', () => {
    assert.throws(() => assertCanAppend([], body({ variants_evaluated: 0 })), /at least one variant/);
    assert.throws(() => assertCanAppend([], body({ cells: -1 })), /cells must be/);
  });
});

describe('importing past run lines', () => {
  it('marks what the old log did not record as unknown, rather than guessing it', () => {
    const imported = bodyFromRunLine({ ts: '2026-11-02T09:00:00Z', dataSha256: 'abc', verdict: 'NO_TRADE', meanR: 0.01, trades: 500 }, 'runs.jsonl');
    assert.equal(imported.record_kind, 'backfill');
    assert.equal(imported.dataset_hash, 'abc');
    assert.equal(imported.date_range.from, null);
    assert.equal(imported.underlying, 'UNKNOWN');
    assert.equal(imported.provenance.sdk_version, 'UNKNOWN');
    assert.equal(imported.variants_evaluated, 1);
  });
});

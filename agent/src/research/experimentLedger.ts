import { createHash } from 'node:crypto';

/**
 * Immutable research experiment ledger (roadmap priority 2).
 *
 * Every variant the research program evaluates is one record. Records are sealed into a hash chain: each carries the
 * hash of the record before it, and its own hash covers its whole body. A record cannot be edited, removed or reordered
 * without `verifyLedger` failing. The multiple-testing divisor reads this ledger, and only this ledger.
 *
 * A new dataset hash is not a new experiment. Overlap is recorded by `overlap_group`, so overlapping observations stay
 * linked to every variant tested on them, and the divisor counts all variants, whatever their dataset.
 */

export type ExperimentType = 'discovery' | 'validation' | 'confirmation';
export type HoldoutStatus = 'Frozen' | 'Spent' | 'NotHoldout';
/** `registration` pre-registers a hypothesis. `experiment` is a run. `backfill` is documented or imported past evidence. */
export type RecordKind = 'registration' | 'experiment' | 'backfill';

export const GENESIS_HASH = 'GENESIS';
export const UNKNOWN = 'UNKNOWN';

export interface Provenance {
  /** The installed broker SDK, e.g. the exact version from package.json. */
  readonly sdk_version: string;
  /** Version of the rolling-option parser that produced the dataset. */
  readonly parser_version: string;
  /** Version of the response layout the parser accepts. */
  readonly response_schema_version: string;
}

export interface LedgerBody {
  readonly record_kind: RecordKind;
  readonly hypothesis_id: string | null;
  readonly strategy_id: string;
  readonly parameter_fingerprint: string;
  readonly dataset_hash: string;
  readonly underlying: string;
  readonly date_range: { readonly from: string | null; readonly to: string | null; readonly label: string | null };
  readonly overlap_group: string;
  readonly experiment_type: ExperimentType;
  readonly holdout_status: HoldoutStatus;
  readonly cells: number;
  readonly variants_evaluated: number;
  readonly costs_fingerprint: string;
  readonly provenance: Provenance;
  readonly result: Record<string, unknown>;
  readonly source: string;
  readonly created_at: string;
}

export interface LedgerRecord extends LedgerBody {
  readonly seq: number;
  readonly prev_hash: string;
  readonly entry_hash: string;
}

export class LedgerIntegrityError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerIntegrityError';
  }
}

export class LedgerRuleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerRuleError';
  }
}

/** JSON with keys sorted at every level, so the same value always produces the same bytes. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function hashOf(value: unknown): string {
  return createHash('sha256').update(canonicalJson(value)).digest('hex');
}

/** Fingerprint of an execution-cost assumption, so two runs at different costs cannot be confused. */
export function costsFingerprint(costs: { readonly halfSpreadPct: number; readonly stopSlippagePct: number }): string {
  return hashOf({ halfSpreadPct: costs.halfSpreadPct, stopSlippagePct: costs.stopSlippagePct });
}

function recordHash(record: unknown): string {
  return hashOf(record);
}

/** Seals a body onto the end of the chain. The caller supplies the body; nothing in it is recomputed here. */
export function seal(body: LedgerBody, previous: LedgerRecord | undefined): LedgerRecord {
  const seq = (previous?.seq ?? 0) + 1;
  const prev_hash = previous?.entry_hash ?? GENESIS_HASH;
  const unsealed = { ...body, seq, prev_hash };
  return { ...unsealed, entry_hash: recordHash(unsealed) };
}

/** Parses the ledger file. A malformed line is an integrity failure, reported by line number. */
export function parseLedger(text: string): LedgerRecord[] {
  return text
    .split('\n')
    .map((line, index) => ({ line, index }))
    .filter(({ line }) => line.trim() !== '')
    .map(({ line, index }) => {
      try {
        return JSON.parse(line) as LedgerRecord;
      } catch {
        throw new LedgerIntegrityError(`ledger line ${index + 1} is not valid JSON`);
      }
    });
}

/**
 * Checks the whole chain: sequence numbers, links, and every record's hash. Throws at the first break. A ledger that
 * fails here must not be used to count variants.
 */
export function verifyLedger(records: readonly LedgerRecord[]): void {
  let previous: LedgerRecord | undefined;
  records.forEach((record, index) => {
    const expectedSeq = index + 1;
    if (record.seq !== expectedSeq) {
      throw new LedgerIntegrityError(`record ${index + 1} has seq ${record.seq}; expected ${expectedSeq}`);
    }
    const expectedPrev = previous?.entry_hash ?? GENESIS_HASH;
    if (record.prev_hash !== expectedPrev) {
      throw new LedgerIntegrityError(`record ${record.seq} does not link to the record before it`);
    }
    const { entry_hash: entryHash, ...rest } = record;
    if (recordHash(rest) !== entryHash) {
      throw new LedgerIntegrityError(`record ${record.seq} was changed after it was sealed`);
    }
    previous = record;
  });
}

/** Every variant the program has evaluated: each record except a registration, which evaluates nothing. */
export function priorVariantCount(records: readonly LedgerRecord[]): number {
  return records.reduce((total, record) => (record.record_kind === 'registration' ? total : total + record.variants_evaluated), 0);
}

/**
 * The overlap group a new observation joins. It joins the group of any earlier record on the same underlying whose date
 * range overlaps it. When either range is unknown, it joins only a record with the same label. Otherwise it opens a new
 * group. Overlap groups count independent evidence; they never reduce the divisor.
 */
export function overlapGroupFor(
  records: readonly LedgerRecord[],
  underlying: string,
  range: { readonly from: string | null; readonly to: string | null; readonly label: string | null },
): string {
  const sameUnderlying = records.filter((record) => record.underlying === underlying);
  const overlapping = sameUnderlying.find((record) => {
    const { from, to, label } = record.date_range;
    if (range.from !== null && range.to !== null && from !== null && to !== null) {
      return range.from <= to && from <= range.to;
    }
    return range.label !== null && label === range.label;
  });
  if (overlapping !== undefined) {
    return overlapping.overlap_group;
  }
  const groups = new Set(records.map((record) => record.overlap_group));
  return `G${groups.size + 1}`;
}

function assertWellFormed(body: LedgerBody): void {
  if (!Number.isInteger(body.variants_evaluated) || body.variants_evaluated < 0) {
    throw new LedgerRuleError('variants_evaluated must be a non-negative integer');
  }
  if (body.record_kind !== 'registration' && body.variants_evaluated < 1) {
    throw new LedgerRuleError('an experiment or backfill evaluated at least one variant');
  }
  if (!Number.isInteger(body.cells) || body.cells < 0) {
    throw new LedgerRuleError('cells must be a non-negative integer');
  }
  const { from, to } = body.date_range;
  if (from !== null && to !== null && from > to) {
    throw new LedgerRuleError('date_range runs backwards');
  }
  if (body.record_kind === 'registration' && (body.hypothesis_id === null || body.hypothesis_id.trim() === '')) {
    throw new LedgerRuleError('a registration needs a hypothesis_id');
  }
}

/**
 * Rules a new run must satisfy before it is sealed. A confirmation needs a registration made before it, on a window that
 * is still Frozen. Only a backfill may record a Spent window, since a backfill documents what happened and does not claim
 * it as a fresh test.
 */
export function assertCanAppend(records: readonly LedgerRecord[], body: LedgerBody): void {
  assertWellFormed(body);
  if (body.record_kind === 'registration') {
    if (records.some((record) => record.record_kind === 'registration' && record.hypothesis_id === body.hypothesis_id)) {
      throw new LedgerRuleError(`hypothesis ${body.hypothesis_id} is already registered`);
    }
    return;
  }
  if (body.record_kind === 'backfill') {
    return;
  }
  if (body.experiment_type === 'confirmation') {
    if (body.holdout_status !== 'Frozen') {
      throw new LedgerRuleError(`a confirmation needs a Frozen window, but this window is ${body.holdout_status}`);
    }
    const registered = records.some((record) => record.record_kind === 'registration' && record.hypothesis_id === body.hypothesis_id);
    if (body.hypothesis_id === null || !registered) {
      throw new LedgerRuleError('a confirmation needs a hypothesis registered before it');
    }
  }
}

/** Seals `body` onto the ledger after the rules pass. Returns the new record and the ledger with it appended. */
export function appendRecord(records: readonly LedgerRecord[], body: LedgerBody): { record: LedgerRecord; records: LedgerRecord[] } {
  verifyLedger(records);
  assertCanAppend(records, body);
  const previous = records[records.length - 1];
  const record = seal(body, previous);
  return { record, records: [...records, record] };
}

/** One runs.jsonl line from the local Time Machine log, imported as a backfill. Its type and window were not recorded, so both say so. */
export function bodyFromRunLine(line: Record<string, unknown>, sourceLabel: string): LedgerBody {
  return {
    record_kind: 'backfill',
    hypothesis_id: null,
    strategy_id: typeof line['strategy'] === 'string' ? line['strategy'] : UNKNOWN,
    parameter_fingerprint: typeof line['configFingerprint'] === 'string' ? line['configFingerprint'] : UNKNOWN,
    dataset_hash: typeof line['dataSha256'] === 'string' ? line['dataSha256'] : UNKNOWN,
    underlying: UNKNOWN,
    date_range: { from: null, to: null, label: null },
    overlap_group: UNKNOWN,
    experiment_type: 'discovery',
    holdout_status: 'NotHoldout',
    // The run log's cell count is cells × prior runs, not a cell count, so the count is not imported.
    cells: 0,
    variants_evaluated: 1,
    costs_fingerprint: UNKNOWN,
    provenance: { sdk_version: UNKNOWN, parser_version: UNKNOWN, response_schema_version: UNKNOWN },
    result: {
      verdict: typeof line['verdict'] === 'string' ? line['verdict'] : UNKNOWN,
      meanR: typeof line['meanR'] === 'number' ? line['meanR'] : UNKNOWN,
      trades: typeof line['trades'] === 'number' ? line['trades'] : UNKNOWN,
      note: 'imported from a local runs.jsonl line; its experiment type, window and underlying were not recorded, so they are marked unknown',
    },
    source: sourceLabel,
    created_at: typeof line['ts'] === 'string' ? line['ts'] : UNKNOWN,
  };
}

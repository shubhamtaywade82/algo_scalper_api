import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { DOCUMENTED_EVIDENCE } from '../src/research/documentedEvidence.js';
import { appendRecord, priorVariantCount, type LedgerBody, type LedgerRecord } from '../src/research/experimentLedger.js';
import { readLedgerFile } from '../src/research/ledgerStore.js';

/**
 * The committed ledger is the research record. These tests keep it honest: the chain verifies, the documented evidence
 * is all present, the spent 2026H window is never relabelled, and the divisor never drops below the floors already recorded.
 */
const LEDGER = fileURLToPath(new URL('../docs/research/experiments.jsonl', import.meta.url));

describe('the committed research ledger', () => {
  it('verifies: its hash chain is intact, so every count taken from it is trustworthy', async () => {
    const records = await readLedgerFile(LEDGER);
    assert.ok(records.length >= DOCUMENTED_EVIDENCE.length);
  });

  it('holds each documented piece of evidence exactly once', async () => {
    const records = await readLedgerFile(LEDGER);
    for (const evidence of DOCUMENTED_EVIDENCE) {
      const matches = records.filter((record) => record.result['evidence_id'] === evidence.evidence_id);
      assert.equal(matches.length, 1, `${evidence.evidence_id} appears ${matches.length} times`);
    }
  });

  it('keeps the 2026H confirmation as Spent, and never as an untouched holdout', async () => {
    const records = await readLedgerFile(LEDGER);
    const confirmation = records.find((record) => record.result['evidence_id'] === 'doc:TIME_MACHINE.md:confirmation-2026H-spent');
    assert.ok(confirmation, 'the 2026H confirmation is preserved');
    assert.equal(confirmation.experiment_type, 'confirmation');
    assert.equal(confirmation.holdout_status, 'Spent');
    assert.equal(records.some((record) => record.date_range.label === 'NIFTY 2026H' && record.holdout_status === 'Frozen'), false);
  });

  it('keeps the 2026H confirmation in the same overlap group as the exit sweep that covered it', async () => {
    const records = await readLedgerFile(LEDGER);
    const group = (id: string) => records.find((record) => record.result['evidence_id'] === id)?.overlap_group;
    assert.equal(group('doc:TIME_MACHINE.md:confirmation-2026H-spent'), group('doc:ROADMAP.md:exit-sweep-nifty-2025-10-2026-09'));
  });

  it('counts at least the variant floors the old seed file recorded, so the divisor has not shrunk', async () => {
    const records = await readLedgerFile(LEDGER);
    assert.ok(priorVariantCount(records) >= 2, 'the exit sweep and the IV-crush floors are still counted');
  });

  it('accepts the documented evidence as a sequence of backfills, so the rules agree with what was recorded', () => {
    let records: LedgerRecord[] = [];
    for (const evidence of DOCUMENTED_EVIDENCE) {
      records = appendRecord(records, evidence.body as LedgerBody).records;
    }
    assert.equal(records.length, DOCUMENTED_EVIDENCE.length);
  });
});

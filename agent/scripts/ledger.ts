/**
 * The research experiment ledger (docs/research/experiments.jsonl). Commands:
 *   verify                         check the hash chain and print the variant count
 *   backfill-docs                  write the evidence documented in the repository, once each
 *   import --runs <runs.jsonl>     write each past local run line once, as an unknown-window backfill
 *   register --hypothesis <id>     pre-register a hypothesis, before any confirmation that tests it
 */
import { readFile } from 'node:fs/promises';
import { DOCUMENTED_EVIDENCE } from '../src/research/documentedEvidence.js';
import { bodyFromRunLine, priorVariantCount, UNKNOWN, type ExperimentType, type HoldoutStatus, type LedgerBody } from '../src/research/experimentLedger.js';
import { appendToLedgerFile, LEDGER_PATH, readLedgerFile } from '../src/research/ledgerStore.js';

const argument = (name: string): string | undefined => {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
};

const evidenceIdsPresent = async (): Promise<Set<unknown>> => {
  const records = await readLedgerFile(LEDGER_PATH);
  return new Set(records.map((record) => record.result['evidence_id']));
};

async function main(): Promise<void> {
  const command = process.argv[2];
  if (command === 'verify') {
    const records = await readLedgerFile(LEDGER_PATH);
    console.log(`ledger ok: ${records.length} records, ${priorVariantCount(records)} variants counted`);
  } else if (command === 'backfill-docs') {
    const present = await evidenceIdsPresent();
    for (const evidence of DOCUMENTED_EVIDENCE) {
      if (present.has(evidence.evidence_id)) {
        console.log(`already present: ${evidence.evidence_id}`);
        continue;
      }
      await appendToLedgerFile(LEDGER_PATH, { ...evidence.body, result: { ...evidence.body.result, evidence_id: evidence.evidence_id } });
      console.log(`backfilled: ${evidence.evidence_id}`);
    }
  } else if (command === 'import') {
    const runsPath = argument('--runs');
    if (runsPath === undefined) {
      throw new Error('import needs --runs <path to runs.jsonl>');
    }
    const present = await evidenceIdsPresent();
    const lines = (await readFile(runsPath, 'utf8')).split('\n').filter((line) => line.trim() !== '');
    let imported = 0;
    for (const [index, text] of lines.entries()) {
      const line = JSON.parse(text) as Record<string, unknown>;
      const evidenceId = `run:${String(line['ts'])}:${String(line['dataSha256'] ?? UNKNOWN)}`;
      if (present.has(evidenceId)) {
        continue;
      }
      const body = bodyFromRunLine(line, `${runsPath} line ${index + 1}`);
      await appendToLedgerFile(LEDGER_PATH, { ...body, result: { ...body.result, evidence_id: evidenceId } });
      imported += 1;
    }
    console.log(`imported ${imported} run line(s); ${lines.length - imported} already present`);
  } else if (command === 'register') {
    const hypothesis = argument('--hypothesis');
    if (hypothesis === undefined) {
      throw new Error('register needs --hypothesis <id>');
    }
    const body: LedgerBody = {
      record_kind: 'registration',
      hypothesis_id: hypothesis,
      strategy_id: argument('--strategy') ?? UNKNOWN,
      parameter_fingerprint: argument('--fingerprint') ?? UNKNOWN,
      dataset_hash: UNKNOWN,
      underlying: argument('--underlying') ?? UNKNOWN,
      date_range: { from: argument('--from') ?? null, to: argument('--to') ?? null, label: argument('--label') ?? null },
      overlap_group: UNKNOWN,
      experiment_type: (argument('--type') ?? 'confirmation') as ExperimentType,
      holdout_status: (argument('--holdout') ?? 'Frozen') as HoldoutStatus,
      cells: 0,
      variants_evaluated: 0,
      costs_fingerprint: UNKNOWN,
      provenance: { sdk_version: UNKNOWN, parser_version: UNKNOWN, response_schema_version: UNKNOWN },
      result: { note: 'pre-registration. The full entry is in docs/research/PREREG.md' },
      source: 'scripts/ledger.ts register',
      created_at: new Date().toISOString(),
    };
    const record = await appendToLedgerFile(LEDGER_PATH, body);
    console.log(`registered ${hypothesis} at seq ${record.seq}`);
  } else {
    throw new Error('usage: tsx scripts/ledger.ts verify | backfill-docs | import --runs <path> | register --hypothesis <id>');
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});

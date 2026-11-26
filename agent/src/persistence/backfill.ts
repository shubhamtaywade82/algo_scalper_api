import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { journalFileName } from '../ops/eventLog.js';
import { repairTornTail } from './journalFile.js';
import { istParts } from '../time/ist.js';
import type { LedgerRecord, PostgresLedger } from './ledger.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface BackfillReport {
  readonly tradingDay: string;
  /** Non-empty lines in the journal file for the day. */
  readonly lines: number;
  /** Lines the ledger did not hold before this backfill. */
  readonly inserted: number;
  /** How a torn final line from a crash was handled, if there was one. */
  readonly tornTail: 'none' | 'completed' | 'quarantined';
}

/**
 * Copies one IST day's journal into the ledger, so the ledger is complete before the day is restored.
 *
 * Lines written by this build carry run and seq and are keyed 'run:seq', the same key the live writer
 * uses, so a line shipped earlier is not inserted twice. Lines from before run ids existed are keyed by
 * their physical line number. The journal is append-only, so that number is stable.
 *
 * The result is verified, not assumed: every key from the file must be present in the ledger afterwards.
 * A malformed line, or a mismatch, throws. A silent gap would under-count losses on restore.
 */
export async function backfillDay(input: {
  readonly directory: string;
  readonly tradingDay: string;
  readonly ledger: PostgresLedger;
}): Promise<BackfillReport> {
  const file = join(input.directory, journalFileName(input.tradingDay));
  const repair = await repairTornTail(file, Date.now());
  let text: string;
  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      return { tradingDay: input.tradingDay, lines: 0, inserted: 0, tornTail: repair.outcome };
    }
    throw error;
  }

  const records = parseJournal(text, input.tradingDay);
  const keys = records.map((record) => record.sourceKey);
  const alreadyPresent = await input.ledger.countSourceKeys(keys);
  if (records.length > 0) {
    await input.ledger.insert(records);
  }
  const present = await input.ledger.countSourceKeys(keys);
  if (present !== records.length) {
    throw new Error(
      `backfill for ${input.tradingDay} is incomplete: ${present} of ${records.length} journal lines are in the ledger; refusing to restore`,
    );
  }
  return {
    tradingDay: input.tradingDay,
    lines: records.length,
    inserted: records.length - alreadyPresent,
    tornTail: repair.outcome,
  };
}

/**
 * Parses the journal into ledger rows. Throws on any line that is not a valid event for this day, and on any gap
 * in a run's sequence within the file. A gap means events were lost before they reached the journal, so nothing
 * restored from it can be trusted to be complete.
 */
export function parseJournal(text: string, tradingDay: string): LedgerRecord[] {
  const records: LedgerRecord[] = [];
  const lastSeqByRun = new Map<string, number>();
  text.split('\n').forEach((raw, index) => {
    if (raw.trim() === '') {
      return;
    }
    const lineNumber = index + 1;
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      throw new Error(`journal line ${lineNumber} is malformed; inspect it before restarting`);
    }
    const ts = typeof event['ts'] === 'string' ? event['ts'] : undefined;
    const type = typeof event['type'] === 'string' ? event['type'] : undefined;
    if (ts === undefined || type === undefined || Number.isNaN(Date.parse(ts))) {
      throw new Error(`journal line ${lineNumber} has no valid timestamp or type; inspect it before restarting`);
    }
    if (istParts(Date.parse(ts)).date !== tradingDay) {
      throw new Error(`journal line ${lineNumber} belongs to another trading day; inspect it before restarting`);
    }

    const run = event['run'];
    const seq = event['seq'];
    const current = typeof run === 'string' && typeof seq === 'number';
    if ((run !== undefined || seq !== undefined) && !current) {
      throw new Error(`journal line ${lineNumber} has a partial run or seq; inspect it before restarting`);
    }
    if (current && !UUID.test(run)) {
      throw new Error(`journal line ${lineNumber} has a run id that is not a UUID; inspect it before restarting`);
    }
    if (current) {
      const previous = lastSeqByRun.get(run);
      if (previous !== undefined && seq !== previous + 1) {
        throw new Error(
          `journal run ${run} jumps from sequence ${previous} to ${seq} at line ${lineNumber}; events were lost before the journal. Refusing to restore`,
        );
      }
      lastSeqByRun.set(run, seq);
    }

    records.push({
      sourceKey: current ? `${run}:${seq}` : `legacy:${tradingDay}:${lineNumber}`,
      runId: current ? run : undefined,
      seq: current ? seq : undefined,
      tradingDay,
      ts,
      eventType: type,
      underlying: typeof event['underlying'] === 'string' ? event['underlying'] : undefined,
      correlationId: typeof event['correlationId'] === 'string' ? event['correlationId'] : undefined,
      record: event,
    });
  });
  return records;
}

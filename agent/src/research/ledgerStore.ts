import { appendFile, mkdir, readFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { appendRecord, parseLedger, verifyLedger, type LedgerBody, type LedgerRecord } from './experimentLedger.js';

/** The committed, append-only ledger. It lives in git, so it survives a fresh clone and is reviewed like code. */
export const LEDGER_PATH = 'docs/research/experiments.jsonl';

/** Reads and verifies the whole ledger. A missing file is an empty ledger. A broken one throws, so no count is taken from it. */
export async function readLedgerFile(path: string = LEDGER_PATH): Promise<LedgerRecord[]> {
  const text = await readFile(path, 'utf8').catch((error: NodeJS.ErrnoException) => {
    if (error.code === 'ENOENT') {
      return '';
    }
    throw error;
  });
  const records = parseLedger(text);
  verifyLedger(records);
  return records;
}

/** Seals one body onto the ledger and appends it. The rules in `assertCanAppend` run first, so a refused run writes nothing. */
export async function appendToLedgerFile(path: string, body: LedgerBody): Promise<LedgerRecord> {
  const records = await readLedgerFile(path);
  const { record } = appendRecord(records, body);
  await mkdir(dirname(path), { recursive: true });
  await appendFile(path, `${JSON.stringify(record)}\n`);
  return record;
}

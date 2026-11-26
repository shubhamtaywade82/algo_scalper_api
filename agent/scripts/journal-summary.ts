/**
 * Summarises one IST trading day for review. It reads only the events of the configured mode and client,
 * so a paper run and a live run can share a directory without their summaries mixing.
 *
 *   npm run journal:summary                              # today, from the journal file in EVENT_LOG_DIR
 *   npm run journal:summary -- 2026-10-12                # a specific day, from the file
 *   npm run journal:summary -- 2026-10-12 --source ledger  # the same day, from the ledger (needs DATABASE_URL)
 *
 * MODE (default paper) and DHAN_CLIENT_ID select the events. Lines without tags predate tagging and are counted, not summarised.
 */
import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { journalFileName } from '../src/ops/eventLog.js';
import { linesInScope, summarizeJournal, type JournalScope } from '../src/ops/journalSummary.js';
import { PostgresLedger } from '../src/persistence/ledger.js';
import { createPostgresPool } from '../src/persistence/postgres.js';
import { errorMessage, secretsOf } from '../src/persistence/redact.js';
import { istParts } from '../src/time/ist.js';

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function main(): Promise<void> {
  const dayKey = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : istParts(Date.now()).date;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) {
    throw new Error(`day must be YYYY-MM-DD, got "${dayKey}"`);
  }
  const scope: JournalScope = { mode: (process.env['MODE'] ?? 'paper').trim().toLowerCase(), clientId: process.env['DHAN_CLIENT_ID']?.trim() ?? '' };
  if (scope.clientId === '') {
    throw new Error('DHAN_CLIENT_ID is required: the summary reads one client\'s events only');
  }
  const source = argument('--source') ?? 'journal';

  let lines: string[];
  let location: string;
  if (source === 'ledger') {
    const url = process.env['DATABASE_URL']?.trim();
    if (url === undefined || url === '') {
      throw new Error('--source ledger needs DATABASE_URL');
    }
    const pool = createPostgresPool({ url, maxConnections: 1, connectTimeoutMs: 5_000, statementTimeoutMs: 15_000, onError: () => undefined });
    try {
      lines = await new PostgresLedger(pool).dayLines(dayKey, scope);
      location = `ledger (${dayKey})`;
    } catch (error) {
      throw new Error(errorMessage(error, secretsOf(url)));
    } finally {
      await pool.end();
    }
  } else {
    const directory = process.env['EVENT_LOG_DIR']?.trim() || 'data/journal';
    const path = join(directory, journalFileName(dayKey));
    const scoped = linesInScope((await readFile(path, 'utf8')).split('\n'), scope);
    lines = scoped.kept;
    location = path;
    if (scoped.untagged > 0) {
      console.log(`note: ${scoped.untagged} untagged line(s) predate mode and client tags and are not included`);
    }
  }

  const summary = summarizeJournal(lines);
  console.log(`events for ${scope.mode} / ${scope.clientId} from ${location}`);
  console.log(JSON.stringify(summary, null, 2));
  if (summary.malformed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

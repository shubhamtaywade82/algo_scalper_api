#!/usr/bin/env node
import 'dotenv/config';
import { existsSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Pool } from 'pg';
import { loadConfig } from '../src/config.js';
import { validatePostgresUrl } from '../src/persistence/urls.js';
import { istParts } from '../src/time/ist.js';

interface ResetStats {
  readonly clientId: string;
  readonly capitalInr: number;
  readonly journalPath: string;
  readonly journalArchived: boolean;
}

function resetJournalFile(journalDir: string, dayKey: string): { path: string; archived: boolean } {
  const filePath = join(journalDir, `events-${dayKey}.jsonl`);
  if (!existsSync(filePath)) {
    return { path: filePath, archived: false };
  }
  const backupPath = join(journalDir, `events-${dayKey}.${Date.now()}.bak`);
  renameSync(filePath, backupPath);
  writeFileSync(filePath, '', 'utf-8');
  return { path: filePath, archived: true };
}

async function resetDatabaseState(databaseUrl: string, clientId: string, capitalInr: number): Promise<void> {
  const pool = new Pool({ connectionString: databaseUrl });
  try {
    await pool.query('TRUNCATE paper_withdrawals, paper_positions, paper_orders, paper_wallet_entries, paper_wallets CASCADE');
    await pool.query(
      'INSERT INTO paper_wallets (client_id, initial_inr, balance_inr) VALUES ($1, $2, $2)',
      [clientId, capitalInr],
    );
    await pool.query("DELETE FROM leases WHERE client_id LIKE 'paper:%'");
    try {
      await pool.query('ALTER TABLE trade_events DISABLE TRIGGER trade_events_immutable');
      await pool.query("DELETE FROM trade_events WHERE record->>'mode' = 'paper' OR run_id IN (SELECT run_id FROM runs WHERE mode = 'paper')");
      await pool.query("DELETE FROM runs WHERE mode = 'paper'");
    } finally {
      await pool.query('ALTER TABLE trade_events ENABLE TRIGGER trade_events_immutable').catch(() => undefined);
    }
  } finally {
    await pool.end();
  }
}

function printResetSummary(stats: ResetStats): void {
  console.log('\n====================== FULL PAPER SESSION RESET ======================');
  console.log(`Client ID:         ${stats.clientId}`);
  console.log(`Starting Balance:  ₹${stats.capitalInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log('Paper Tables:      paper_positions, paper_orders, paper_wallets (CLEARED)');
  console.log(`Daily Journal:     ${stats.journalPath} (${stats.journalArchived ? 'ARCHIVED & RESET' : 'FRESH'})`);
  console.log('Today Metrics:     P&L ₹0.00 | 0 Trades | 0 Open Positions');
  console.log('Cockpit State:     CLEAN SLATE — Ready for new trading session');
  console.log('======================================================================\n');
}

async function main(): Promise<void> {
  const config = loadConfig(process.env, 'config.paper.yml');
  const databaseUrl = config.persistence.databaseUrl;
  if (!databaseUrl) {
    throw new Error('DATABASE_URL is required for paper mode persistence');
  }
  validatePostgresUrl(databaseUrl);

  const clientId = config.dhan.clientId;
  const capitalInr = config.capital.inr;
  const today = istParts(Date.now()).date;

  await resetDatabaseState(databaseUrl, clientId, capitalInr);
  const journalResult = resetJournalFile(config.ops.eventLogDir, today);

  printResetSummary({
    clientId,
    capitalInr,
    journalPath: journalResult.path,
    journalArchived: journalResult.archived,
  });
}

main().catch((error) => {
  console.error(`reset:paper failed: ${(error as Error).message}`);
  process.exit(1);
});

/**
 * Operator commands for the trading ledger. Each one needs DATABASE_URL, from the environment or .env.
 *
 *   npm run db:status
 *       Applied migrations, the current trading lease, and live runs that never ended.
 *   npm run db:migrate
 *       Applies pending migrations and exits. The agent also applies them at start.
 *   npm run db:acknowledge -- --run <runId> --reason "<what you checked at the broker>"
 *       Records that a run which never ended has been reviewed, so a new live run can start.
 *       The reason is kept on the run row. A run is acknowledged once.
 */
import 'dotenv/config';
import { createPostgresPool, migrate } from '../src/persistence/postgres.js';
import { MIGRATIONS } from '../src/persistence/migrations.js';
import { PostgresLedger } from '../src/persistence/ledger.js';
import { errorMessage, secretsOf } from '../src/persistence/redact.js';
import { validatePostgresUrl } from '../src/persistence/urls.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function main(): Promise<void> {
  const command = process.argv[2];
  const url = process.env['DATABASE_URL']?.trim();
  if (url === undefined || url === '') {
    throw new Error('DATABASE_URL is required');
  }
  const secrets = secretsOf(url);
  let pool: ReturnType<typeof createPostgresPool> | undefined;
  try {
    validatePostgresUrl(url);
    pool = createPostgresPool({ url, maxConnections: 2, connectTimeoutMs: 5_000, statementTimeoutMs: 15_000, onError: () => undefined });
    const ledger = new PostgresLedger(pool);
    if (command === 'migrate') {
      const report = await migrate(pool, MIGRATIONS);
      console.log(`applied: ${report.applied.length === 0 ? 'none (already current)' : report.applied.join(', ')}`);
    } else if (command === 'status') {
      const applied = await pool.query<{ version: string; applied_at: Date }>('SELECT version, applied_at FROM schema_migrations ORDER BY version');
      console.log('migrations:');
      for (const row of applied.rows) {
        console.log(`  ${row.version}  applied ${row.applied_at.toISOString()}`);
      }
      const leases = await pool.query<{ client_id: string; holder_run: string; epoch: string; expires_at: Date; held: boolean }>(
        'SELECT client_id, holder_run::text AS holder_run, epoch::text AS epoch, expires_at, expires_at > now() AS held FROM leases ORDER BY client_id',
      );
      console.log('trading leases:');
      for (const row of leases.rows) {
        console.log(`  ${row.client_id}  run ${row.holder_run}  epoch ${row.epoch}  ${row.held ? `held until ${row.expires_at.toISOString()}` : 'free'}`);
      }
      const unended = await pool.query<{ run_id: string; mode: string; client_id: string; instance_id: string; started_at: Date }>(
        'SELECT run_id::text AS run_id, mode, client_id, instance_id, started_at FROM runs WHERE ended_at IS NULL ORDER BY started_at',
      );
      console.log(`runs that never ended (any mode): ${unended.rows.length}`);
      for (const row of unended.rows) {
        console.log(`  ${row.run_id}  ${row.mode}  client ${row.client_id}  instance ${row.instance_id}  started ${row.started_at.toISOString()}`);
      }
    } else if (command === 'acknowledge') {
      const runId = argument('--run');
      const reason = argument('--reason')?.trim();
      if (runId === undefined || !UUID.test(runId)) {
        throw new Error('--run must be the run id, a UUID');
      }
      if (reason === undefined || reason.length < 10) {
        throw new Error('--reason must say what was checked, at least 10 characters');
      }
      const closed = await ledger.acknowledgeRun(runId, reason);
      if (closed === 0) {
        throw new Error(`run ${runId} is not open; nothing was acknowledged`);
      }
      console.log(`acknowledged run ${runId}`);
    } else if (command === 'reset-wallet') {
      const clientId = argument('--client') ?? process.env['DHAN_CLIENT_ID'];
      if (!clientId) {
        throw new Error('--client or DHAN_CLIENT_ID is required');
      }
      const rawAmount = argument('--amount') ?? process.env['CAPITAL_INR'] ?? '1000000';
      const amount = Number(rawAmount);
      if (process.argv.includes('--clean')) {
        await pool.query('TRUNCATE paper_wallets CASCADE');
      }
      await pool.query(
        'INSERT INTO paper_wallets (client_id, initial_inr, balance_inr) VALUES ($1, $2, $2) ON CONFLICT (client_id) DO UPDATE SET initial_inr = $2, balance_inr = $2, updated_at = now()',
        [clientId, amount],
      );
      console.log(`paper wallet for client ${clientId} reset to ${amount} INR${process.argv.includes('--clean') ? ' (clean slate)' : ''}`);
    } else {
      throw new Error('usage: db.ts migrate | status | acknowledge --run <runId> --reason "<text>" | reset-wallet [--client <id>] [--amount <inr>] [--clean]');
    }
  } catch (error) {
    console.error(`db: ${errorMessage(error, secrets)}`);
    process.exitCode = 1;
  } finally {
    await pool?.end();
  }
}

void main();

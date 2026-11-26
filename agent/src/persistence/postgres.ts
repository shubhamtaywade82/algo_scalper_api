import { createHash } from 'node:crypto';
import { Pool } from 'pg';

export interface PostgresOptions {
  readonly url: string;
  readonly maxConnections: number;
  readonly connectTimeoutMs: number;
  readonly statementTimeoutMs: number;
  /** Idle-client errors are reported here. Without a listener, pg would crash the process. */
  readonly onError: (error: Error) => void;
}

export function createPostgresPool(options: PostgresOptions): Pool {
  const pool = new Pool({
    connectionString: options.url,
    max: options.maxConnections,
    connectionTimeoutMillis: options.connectTimeoutMs,
    idleTimeoutMillis: 30_000,
    statement_timeout: options.statementTimeoutMs,
    // A connection the network silently dropped must fail, not hang the caller until the kernel gives up.
    query_timeout: options.statementTimeoutMs + 2_000,
    keepAlive: true,
    application_name: 'options-trading-agent',
  });
  pool.on('error', (error) => options.onError(error));
  return pool;
}

export interface Migration {
  readonly version: string;
  readonly sql: string;
}

export interface MigrationReport {
  readonly applied: readonly string[];
  readonly alreadyApplied: number;
}

/** Advisory-lock key that serialises migrations across processes. */
const MIGRATION_LOCK_KEY = 727_001;

export function migrationChecksum(sql: string): string {
  return createHash('sha256').update(sql).digest('hex');
}

/**
 * Applies pending migrations in order, each in its own transaction, under a session advisory lock so
 * two processes cannot migrate at once. Refuses to run when an applied migration has changed since
 * it was applied, or when the database holds a migration this build does not know.
 */
export async function migrate(pool: Pool, migrations: readonly Migration[]): Promise<MigrationReport> {
  assertOrdered(migrations);
  const client = await pool.connect();
  let lockHeld = false;
  try {
    // A migration can legitimately take longer than the request timeout, such as an index build. Its own session sets the limit.
    await client.query("SET statement_timeout = 0; SET lock_timeout = '30s'");
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    lockHeld = true;
    await client.query(
      'CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())',
    );
    const { rows } = await client.query<{ version: string; checksum: string }>('SELECT version, checksum FROM schema_migrations');
    const applied = new Map(rows.map((row) => [row.version, row.checksum]));
    const known = new Set(migrations.map((migration) => migration.version));
    for (const version of applied.keys()) {
      if (!known.has(version)) {
        throw new Error(`database has migration ${version} that this build does not know; refusing to start`);
      }
    }

    const ran: string[] = [];
    for (const migration of migrations) {
      const sum = migrationChecksum(migration.sql);
      const existing = applied.get(migration.version);
      if (existing !== undefined) {
        if (existing !== sum) {
          throw new Error(`migration ${migration.version} changed after it was applied; refusing to start`);
        }
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(migration.sql);
        await client.query('INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)', [migration.version, sum]);
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }
      ran.push(migration.version);
    }
    return { applied: ran, alreadyApplied: applied.size };
  } finally {
    let unlockFailed = false;
    if (lockHeld) {
      try {
        await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY]);
      } catch {
        unlockFailed = true;
      }
    }
    // A connection whose unlock failed is destroyed, so the session lock cannot outlive this call.
    // Otherwise the migration timeouts are reset before the connection returns to the pool.
    if (!unlockFailed) {
      await client.query('RESET statement_timeout; RESET lock_timeout').catch(() => {
        unlockFailed = true;
      });
    }
    client.release(unlockFailed);
  }
}

function assertOrdered(migrations: readonly Migration[]): void {
  const seen = new Set<string>();
  let previous = '';
  for (const migration of migrations) {
    if (seen.has(migration.version) || migration.version <= previous) {
      throw new Error(`migration versions must be unique and ascending; saw ${migration.version} after ${previous || 'start'}`);
    }
    seen.add(migration.version);
    previous = migration.version;
  }
}

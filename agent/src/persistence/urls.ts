/**
 * URL parsing for the persistence layer. This module has no driver dependencies, so configuration can
 * validate connection strings without loading a database client. Parser messages never include the input.
 */

export interface ParsedRedisUrl {
  readonly host: string;
  readonly port: number;
  readonly username: string | undefined;
  readonly password: string | undefined;
  readonly db: number;
  readonly tls: boolean;
}

export function parseRedisUrl(url: string): ParsedRedisUrl {
  const parsed = parseUrl(url, 'REDIS_URL');
  if (parsed.protocol !== 'redis:' && parsed.protocol !== 'rediss:') {
    throw new Error('REDIS_URL must use the redis:// or rediss:// scheme');
  }
  const dbPath = parsed.pathname.replace(/^\//, '');
  const db = dbPath === '' ? 0 : Number(dbPath);
  if (!Number.isInteger(db) || db < 0) {
    throw new Error('REDIS_URL database index must be a non-negative integer');
  }
  return {
    host: parsed.hostname,
    port: parsed.port === '' ? 6379 : Number(parsed.port),
    username: parsed.username === '' ? undefined : decodeURIComponent(parsed.username),
    password: parsed.password === '' ? undefined : decodeURIComponent(parsed.password),
    db,
    tls: parsed.protocol === 'rediss:',
  };
}

/** Checks the scheme and host of a PostgreSQL URL. The driver itself reads the rest of the string. */
export function validatePostgresUrl(url: string): void {
  const parsed = parseUrl(url, 'DATABASE_URL');
  if (parsed.protocol !== 'postgres:' && parsed.protocol !== 'postgresql:') {
    throw new Error('DATABASE_URL must use the postgres:// or postgresql:// scheme');
  }
  if (parsed.hostname === '') {
    throw new Error('DATABASE_URL must name a host');
  }
}

function parseUrl(url: string, name: string): URL {
  try {
    return new URL(url);
  } catch {
    throw new Error(`${name} is not a valid URL`);
  }
}

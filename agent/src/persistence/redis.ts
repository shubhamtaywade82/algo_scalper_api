import { Redis } from 'ioredis';
import { errorMessage, secretsOf } from './redact.js';
import { parseRedisUrl } from './urls.js';

export interface RedisOptions {
  readonly url: string;
  readonly connectTimeoutMs: number;
  readonly commandTimeoutMs: number;
  readonly onError: (error: Error) => void;
}

/**
 * Builds a Redis client with fail-fast behaviour. Commands issued while disconnected reject at once
 * instead of queueing, so a lock renewal or a rate-gate check cannot wait behind a dead connection.
 */
export function createRedisClient(options: RedisOptions): Redis {
  const parsed = parseRedisUrl(options.url);
  const client = new Redis({
    host: parsed.host,
    port: parsed.port,
    ...(parsed.username === undefined ? {} : { username: parsed.username }),
    ...(parsed.password === undefined ? {} : { password: parsed.password }),
    db: parsed.db,
    ...(parsed.tls ? { tls: {} } : {}),
    lazyConnect: true,
    connectTimeout: options.connectTimeoutMs,
    commandTimeout: options.commandTimeoutMs,
    maxRetriesPerRequest: 1,
    enableOfflineQueue: false,
    retryStrategy: (attempt: number) => Math.min(attempt * 200, 2_000),
  });
  client.on('error', (error: Error) => options.onError(error));
  return client;
}

/** Opens the connection and proves it with PING. Errors are redacted before they leave this function. */
export async function connectRedis(options: RedisOptions): Promise<Redis> {
  const client = createRedisClient(options);
  try {
    await client.connect();
    const reply = await client.ping();
    if (reply !== 'PONG') {
      throw new Error(`unexpected PING reply ${reply}`);
    }
    return client;
  } catch (error) {
    client.disconnect();
    throw new Error(`Redis is not reachable: ${errorMessage(error, secretsOf(options.url))}`);
  }
}

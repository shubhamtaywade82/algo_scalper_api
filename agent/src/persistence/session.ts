import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';
import type { Pool } from 'pg';
import type { Redis } from 'ioredis';
import { configFingerprint, type AgentConfig } from '../config.js';
import type { TradingMode } from '../domain/mode.js';
import type { Logger } from '../ops/logger.js';
import { MemoryCacheStore, RedisCacheStore, type CacheStore } from './cache.js';
import { Lease, PostgresLeaseStore } from './lease.js';
import { PostgresLedger, type LedgerFence } from './ledger.js';
import { MIGRATIONS } from './migrations.js';
import { createPostgresPool, migrate } from './postgres.js';
import { connectRedis } from './redis.js';
import { MemoryRateGate, RedisRateGate, ReservationRateGate, type RateGate } from './rateGate.js';
import { errorMessage, secretsOf } from './redact.js';

/** Key namespace for everything this agent writes to Redis. Per client id, so two accounts never collide. */
const KEY_ROOT = 'dhan-agent';

export interface PersistenceSession {
  readonly runId: string;
  /** Present when DATABASE_URL is set. Every write through it is fenced to the lease. */
  readonly ledger: PostgresLedger | undefined;
  /** The PostgreSQL pool and the lease fence, for stores that keep their own tables, such as the paper venue. */
  readonly pool: Pool | undefined;
  readonly fence: LedgerFence | undefined;
  readonly cache: CacheStore;
  readonly rateGate: RateGate;
  /**
   * The Redis client whenever REDIS_URL is set. Read-only consumers (the shared
   * chain-context reader) may use it directly; closing it stays the session's
   * job, consumers must not disconnect it.
   */
  readonly redis: Redis | undefined;
  /** Present whenever DATABASE_URL is set. The trading right for this account, held in PostgreSQL. */
  readonly lease: Lease | undefined;
  /** Strings that must never appear in a log line or error message. */
  readonly secrets: readonly string[];
  /**
   * Ends the run record, releases the lease and closes connections. `unconfirmed` is how many events were not yet
   * in the journal and ledger at that moment; a non-zero count makes the next live start wait for review. Idempotent.
   */
  close(reason: string, unconfirmed?: number): Promise<void>;
}

/** Memory without Redis; the shared Rails-compatible line when asked for; otherwise this agent's own per-account gate. */
function buildRateGate(redis: Redis | undefined, config: AgentConfig, now: () => number): RateGate {
  if (redis === undefined) {
    return new MemoryRateGate({ now });
  }
  const { sharedRateLimitKey } = config.persistence;
  if (sharedRateLimitKey !== undefined) {
    return new ReservationRateGate(redis, { key: sharedRateLimitKey, now });
  }
  return new RedisRateGate(redis, { prefix: `${KEY_ROOT}:${config.dhan.clientId}:rl:` });
}

/**
 * The account a lease and its fence belong to. Live, sandbox and paper are different accounts or different
 * books, so each mode holds its own lease. Two runs of the same mode for the same client never both trade.
 */
export function accountKey(mode: TradingMode, clientId: string): string {
  return `${mode}:${clientId}`;
}

/**
 * Opens every configured store and registers the run. Any run with a ledger takes the account's trading lease
 * and refuses to start while an earlier run of the same mode and client never ended, because that run may still
 * hold orders or positions that this process has not seen. Any failure closes what was opened and throws a
 * redacted error, so a refused start leaves nothing connected and never prints a credential.
 */
export async function openSession(
  config: AgentConfig,
  input: { readonly logger: Logger; readonly now: () => number },
): Promise<PersistenceSession> {
  const { logger } = input;
  const { databaseUrl, redisUrl, leaseTtlMs, postgresMaxConnections } = config.persistence;
  const clientId = config.dhan.clientId;
  const account = accountKey(config.mode, clientId);
  const secrets = [...(databaseUrl === undefined ? [] : secretsOf(databaseUrl)), ...(redisUrl === undefined ? [] : secretsOf(redisUrl))];
  const runId = randomUUID();
  const instance = config.persistence.instanceId ?? hostname();

  let pool: Pool | undefined;
  let leasePool: Pool | undefined;
  let redis: Redis | undefined;
  let lease: Lease | undefined;
  let fence: LedgerFence | undefined;
  let ledger: PostgresLedger | undefined;
  let runRegistered = false;
  let closing: Promise<void> | undefined;

  const close = (reason: string, unconfirmed = 0): Promise<void> => {
    closing ??= (async () => {
      if (ledger !== undefined && runRegistered) {
        await ledger.endRun(runId, reason, unconfirmed).catch((error: unknown) => {
          logger.error('could not mark the run ended', { runId, error: errorMessage(error, secrets) });
        });
      }
      if (lease !== undefined) {
        const immediateHandoff = reason === 'aborted' && config.mode === 'paper';
        await lease.release(immediateHandoff).catch((error: unknown) => {
          logger.error('could not release the trading lease', { error: errorMessage(error, secrets) });
        });
      }
      redis?.disconnect();
      for (const toClose of [leasePool, pool]) {
        await toClose?.end().catch((error: unknown) => {
          logger.warn('ledger pool did not close cleanly', { error: errorMessage(error, secrets) });
        });
      }
    })();
    return closing;
  };

  try {
    if (databaseUrl !== undefined) {
      pool = createPostgresPool({
        url: databaseUrl,
        maxConnections: postgresMaxConnections,
        connectTimeoutMs: 5_000,
        statementTimeoutMs: 10_000,
        onError: (error) => logger.error('ledger connection error', { error: errorMessage(error, secrets) }),
      });
      const report = await migrate(pool, MIGRATIONS);
      logger.info('ledger schema ready', { applied: [...report.applied], alreadyApplied: report.alreadyApplied });

      // The lease has its own single connection, with a timeout below the renewal interval. A busy event
      // outbox must never delay a renewal, and a stalled renewal must show up as a lost lease, not a hang.
      leasePool = createPostgresPool({
        url: databaseUrl,
        maxConnections: 1,
        connectTimeoutMs: 5_000,
        statementTimeoutMs: Math.max(1_000, Math.floor(leaseTtlMs / 3)),
        onError: (error) => logger.error('lease connection error', { error: errorMessage(error, secrets) }),
      });
      // Created before the ledger, because every ledger write is fenced to the lease's epoch.
      lease = new Lease(new PostgresLeaseStore(leasePool), {
        clientId: account,
        runId,
        ttlMs: leaseTtlMs,
        // A new holder waits this long after expiry, so an order that was in flight can still finish.
        // Paper mode has no exchange order queues, so its margin is 0.
        marginMs: config.mode === 'paper' ? 0 : config.ops.orderTimeoutMs,
        // Elapsed time since the last renewal is measured in this process, so it uses a monotonic clock. A wall
        // clock step backwards would otherwise keep the lease "held" after its ttl has passed.
        now: () => performance.now(),
      });
      fence = { clientId: account, runId, epoch: () => lease?.epoch() };
      ledger = new PostgresLedger(pool, fence);
    }

    if (redisUrl !== undefined) {
      redis = await connectRedis({
        url: redisUrl,
        connectTimeoutMs: 5_000,
        commandTimeoutMs: 3_000,
        onError: (error) => logger.warn('redis connection error', { error: errorMessage(error, secrets) }),
      });
    }

    // Redis holds the account rate gate and the contract cache. Neither is a trading authority.
    const cache: CacheStore = redis === undefined ? new MemoryCacheStore(input.now) : new RedisCacheStore(redis, `${KEY_ROOT}:${clientId}:cache:`);
    const rateGate = buildRateGate(redis, config, input.now);

    if (ledger !== undefined) {
      await ledger.startRun({
        runId,
        instanceId: instance,
        mode: config.mode,
        clientId,
        configFingerprint: configFingerprint(config),
        startedAt: new Date(input.now()).toISOString(),
      });
      runRegistered = true;
    }

    if (lease !== undefined && ledger !== undefined) {
      const isPaper = config.mode === 'paper';
      if (!(await lease.acquire())) {
        throw new Error(
          `another run holds the trading lease for ${account}. A crashed run releases it when its lease expires, plus the order timeout; start again after that`,
        );
      }
      logger.info('trading lease acquired', { account, runId });
      const review = await ledger.runsNeedingReview(clientId, config.mode, runId);
      if (review.length > 0) {
        if (isPaper) {
          for (const unended of review) {
            await ledger.acknowledgeRun(unended.runId, `auto-reconciled on paper restart (${unended.reason})`);
          }
          logger.warn('auto-reconciled unended paper runs from prior session', {
            count: review.length,
            runIds: review.map((r) => r.runId),
          });
        } else {
          const list = review.map((r) => `${r.runId} (${r.instanceId}, started ${r.startedAt}, ${r.reason})`).join('; ');
          throw new Error(
            `${config.mode} runs for client ${clientId} need review before this one starts: ${list}. Check their positions and orders, then run npm run db:acknowledge -- --run <runId> --reason "<what you checked>"`,
          );
        }
      }
      lease.onLost((reason) => logger.error('trading lease lost; no new entries will be sent', { reason }));
      // Live keeps a lost lease lost: a human checks the account first. Paper takes it back once it is free.
      if (isPaper) {
        lease.reacquireAfterLoss(config.persistence.leaseTtlMs, () => logger.info('trading lease re-acquired', { account, runId }));
      }
    }

    return { runId, ledger, pool, fence, cache, rateGate, redis, lease, secrets, close };
  } catch (error) {
    await close('startup failed');
    throw new Error(`persistence startup failed: ${errorMessage(error, secrets)}`);
  }
}

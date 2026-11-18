import type { Redis } from 'ioredis';

/**
 * Spaces calls so consecutive acquisitions under one key are at least `windowMs` apart. Used for
 * account-wide limits, which one process cannot enforce alone when two processes share an account.
 */
export interface RateGate {
  acquire(key: string, windowMs: number): Promise<void>;
}

export interface MemoryRateGateOptions {
  readonly now?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
}

export class MemoryRateGate implements RateGate {
  private readonly last = new Map<string, number>();
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(options: MemoryRateGateOptions = {}) {
    this.now = options.now ?? Date.now;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  async acquire(key: string, windowMs: number): Promise<void> {
    const previous = this.last.get(key);
    if (previous !== undefined) {
      const wait = previous + windowMs - this.now();
      if (wait > 0) {
        await this.sleep(wait);
      }
    }
    this.last.set(key, this.now());
  }
}

export interface RedisRateGateOptions {
  readonly prefix: string;
  readonly sleep?: (ms: number) => Promise<void>;
  /** Attempts before giving up. Each attempt waits for the current window to close. */
  readonly maxAttempts?: number;
}

/**
 * A slot is claimed with SET NX PX, so exactly one caller wins each window across every process.
 * A caller that loses waits for the remaining TTL of the winning slot, then tries again.
 */
export class RedisRateGate implements RateGate {
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly maxAttempts: number;

  constructor(
    private readonly redis: Redis,
    private readonly options: RedisRateGateOptions,
  ) {
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.maxAttempts = options.maxAttempts ?? 50;
  }

  async acquire(key: string, windowMs: number): Promise<void> {
    const slot = `${this.options.prefix}${key}`;
    for (let attempt = 0; attempt < this.maxAttempts; attempt += 1) {
      const claimed = await this.redis.set(slot, '1', 'PX', windowMs, 'NX');
      if (claimed === 'OK') {
        return;
      }
      const remaining = await this.redis.pttl(slot);
      await this.sleep(remaining > 0 ? remaining : 1);
    }
    throw new Error(`rate gate ${key} did not open after ${this.maxAttempts} attempts`);
  }
}

/**
 * The same Lua reservation the Rails app's `Dhan::SharedRateLimit` runs: each caller reserves the next free slot
 * and pushes the following one `gap` later, so every process on the account queues in one line. It must stay
 * byte-for-byte compatible with that script, because both sides read and write the same key.
 */
const RESERVE_SLOT = `
local now = tonumber(ARGV[1])
local gap = tonumber(ARGV[2])
local next_free = tonumber(redis.call('GET', KEYS[1]) or '0')
local slot = math.max(now, next_free)
redis.call('SET', KEYS[1], tostring(slot + gap), 'PX', 60000)
return tostring(slot)
`;

/** Rails stops waiting after this and proceeds; matching it keeps one side from starving the other. */
const MAX_WAIT_MS = 10_000;

export interface ReservationRateGateOptions {
  /** The shared key, for example `dhan:rate_limit:option_chain`. Dhan limits per account and this Redis serves one account. */
  readonly key: string;
  readonly now?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
}

export class ReservationRateGate implements RateGate {
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(
    private readonly redis: Redis,
    private readonly options: ReservationRateGateOptions,
  ) {
    this.now = options.now ?? Date.now;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  /** The `key` argument names the account; here the shared key already stands for it, so it is not used. */
  async acquire(_key: string, windowMs: number): Promise<void> {
    const nowSeconds = this.now() / 1000;
    const slotSeconds = Number(await this.redis.eval(RESERVE_SLOT, 1, this.options.key, String(nowSeconds), String(windowMs / 1000)));
    const waitMs = Math.min((slotSeconds - nowSeconds) * 1000, MAX_WAIT_MS);
    if (waitMs > 0) {
      await this.sleep(waitMs);
    }
  }
}

import type { Redis } from 'ioredis';

/**
 * Derived, re-computable data only: contract lists and similar. Never tokens, positions, orders,
 * fills or P&L. A missing or corrupt entry is a miss, so callers must be able to rebuild the value.
 */
export interface CacheStore {
  get<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown, ttlMs: number): Promise<void>;
}

export class MemoryCacheStore implements CacheStore {
  private readonly entries = new Map<string, { value: string; expiresAt: number }>();

  constructor(private readonly now: () => number = Date.now) {}

  async get<T>(key: string): Promise<T | undefined> {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    if (this.now() >= entry.expiresAt) {
      this.entries.delete(key);
      return undefined;
    }
    return JSON.parse(entry.value) as T;
  }

  async set(key: string, value: unknown, ttlMs: number): Promise<void> {
    this.entries.set(key, { value: JSON.stringify(value), expiresAt: this.now() + ttlMs });
  }
}

export class RedisCacheStore implements CacheStore {
  constructor(
    private readonly redis: Redis,
    private readonly prefix: string,
  ) {}

  async get<T>(key: string): Promise<T | undefined> {
    const raw = await this.redis.get(this.key(key));
    if (raw === null) {
      return undefined;
    }
    try {
      return JSON.parse(raw) as T;
    } catch {
      // A corrupt entry is a miss. The caller rebuilds it and overwrites it.
      return undefined;
    }
  }

  async set(key: string, value: unknown, ttlMs: number): Promise<void> {
    await this.redis.set(this.key(key), JSON.stringify(value), 'PX', Math.max(1, Math.floor(ttlMs)));
  }

  private key(key: string): string {
    return `${this.prefix}${key}`;
  }
}

/** Milliseconds from now until the next IST midnight, so a per-day cache entry expires at the day boundary. */
export function msUntilNextIstMidnight(nowMs: number): number {
  const istOffsetMs = 19_800_000;
  const dayMs = 86_400_000;
  const istMs = nowMs + istOffsetMs;
  return dayMs - (((istMs % dayMs) + dayMs) % dayMs);
}

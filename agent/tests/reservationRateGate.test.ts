import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Redis } from 'ioredis';
import { ReservationRateGate } from '../src/persistence/rateGate.js';

/**
 * Stands in for Redis by running the reservation the Lua script performs, so the test pins what the gate sends
 * (key, clock in seconds, gap in seconds) and how it reacts to the slot it gets back.
 */
function fakeRedis(): { redis: Redis; evals: { key: string; now: number; gap: number }[] } {
  const slots = new Map<string, number>();
  const evals: { key: string; now: number; gap: number }[] = [];
  const redis = {
    eval: async (_script: string, _numKeys: number, key: string, now: string, gap: string): Promise<string> => {
      evals.push({ key, now: Number(now), gap: Number(gap) });
      const slot = Math.max(Number(now), slots.get(key) ?? 0);
      slots.set(key, slot + Number(gap));
      return String(slot);
    },
  } as unknown as Redis;
  return { redis, evals };
}

describe('ReservationRateGate', () => {
  function gateAt(clock: { ms: number }, redis: Redis) {
    const slept: number[] = [];
    const gate = new ReservationRateGate(redis, {
      key: 'dhan:rate_limit:option_chain',
      now: () => clock.ms,
      sleep: async (ms) => {
        slept.push(ms);
        clock.ms += ms;
      },
    });
    return { gate, slept };
  }

  it('claims a slot under the shared key, in the units the Rails limiter uses', async () => {
    const { redis, evals } = fakeRedis();
    const { gate } = gateAt({ ms: 1_000_000 }, redis);

    await gate.acquire('any-account', 3_000);

    assert.deepEqual(evals, [{ key: 'dhan:rate_limit:option_chain', now: 1_000, gap: 3 }]);
  });

  it('does not wait when the slot is free, and spaces the next caller by the gap', async () => {
    const { redis } = fakeRedis();
    const clock = { ms: 1_000_000 };
    const { gate, slept } = gateAt(clock, redis);

    await gate.acquire('a', 3_000);
    assert.deepEqual(slept, []);

    await gate.acquire('a', 3_000);
    assert.deepEqual(slept, [3_000]);
  });

  it('queues behind a slot another process already reserved', async () => {
    const { redis } = fakeRedis();
    const clock = { ms: 1_000_000 };
    const first = gateAt(clock, redis);
    const second = gateAt(clock, redis);

    await first.gate.acquire('a', 3_000);
    await second.gate.acquire('a', 3_000);

    assert.deepEqual(second.slept, [3_000]);
  });
});

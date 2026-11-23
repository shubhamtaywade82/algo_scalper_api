import type { Redis } from 'ioredis';
import { z } from 'zod';
import type { Direction } from '../domain/types.js';
import type { OiWall } from './chainAnalyzer.js';

/**
 * The shared chain truth (contract `chain-context/1`, vendored at
 * contracts/schemas/chain-context-1.schema.json). algo_scalper_api publishes
 * the computed analytics for each underlying's chain to Redis
 * `dhan:chain:context:{UNDERLYING}` after every chain-watch refresh; this
 * module reads it so the agent's OI-resistance gate runs on the same numbers
 * Rails already computed instead of re-deriving them from the agent's own
 * chain fetch.
 *
 * Share data, not decisions: the bias/verdict are advisory inputs. The agent
 * still applies its own policy (headroom minimums, PCR bands) through
 * {@link sharedChainAnalysis} -> the existing
 * {@link checkOptionBuyingConfluence} gate. When the snapshot is missing,
 * unreadable, or stale past `maxAgeMs`, the reader returns undefined and the
 * caller falls back to its own local computation - the pre-existing
 * behaviour, so Rails-down degrades to what the agent did before this
 * contract existed.
 */
export const CHAIN_CONTEXT_KEY_PREFIX = 'dhan:chain:context';

/** How old a snapshot may be before the agent prefers its own numbers. */
export const DEFAULT_MAX_AGE_MS = 10_000;

const chainContextSchema = z.object({
  schema: z.literal('chain-context/1'),
  underlying: z.string(),
  expiry: z.string(),
  spot: z.number().positive(),
  computed_at_ms: z.number().int(),
  source: z.string(),
  window_strikes: z.number().int(),
  pcr: z.number(),
  atm_pcr: z.number(),
  call_resistance: z.object({ strike: z.number(), oi: z.number().int(), distance: z.number() }),
  put_support: z.object({ strike: z.number(), oi: z.number().int(), distance: z.number() }),
  headroom_ce: z.number(),
  headroom_pe: z.number(),
  straddle_premium: z.number(),
  expected_range: z.object({ lower: z.number(), upper: z.number() }),
  sentiment_score: z.number().int(),
  bias: z.enum(['BULLISH', 'BEARISH', 'NEUTRAL']),
  verdict: z.string(),
});

export type ChainContextSnapshot = z.infer<typeof chainContextSchema>;

export interface SharedChainContextOptions {
  /** The agent's own Redis (the same one Rails publishes to). */
  readonly redis: Pick<Redis, 'get'>;
  readonly underlying: string;
  readonly maxAgeMs?: number;
  readonly now?: () => number;
}

export interface SharedChainContextReader {
  /** Latest valid snapshot, or undefined when missing/unreadable/stale. Never throws. */
  readonly read: () => Promise<ChainContextSnapshot | undefined>;
}

export function sharedChainContextKey(underlying: string): string {
  return `${CHAIN_CONTEXT_KEY_PREFIX}:${underlying.toUpperCase()}`;
}

export function createSharedChainContextReader(options: SharedChainContextOptions): SharedChainContextReader {
  const maxAgeMs = options.maxAgeMs ?? DEFAULT_MAX_AGE_MS;
  const now = options.now ?? Date.now;
  const key = sharedChainContextKey(options.underlying);

  return {
    async read(): Promise<ChainContextSnapshot | undefined> {
      try {
        const raw = await options.redis.get(key);
        if (raw === null || raw.length === 0) {
          return undefined;
        }
        const parsed = chainContextSchema.safeParse(JSON.parse(raw));
        if (!parsed.success) {
          return undefined; // a contract drift must not break trading; fall back
        }
        const snapshot = parsed.data;
        const age = now() - snapshot.computed_at_ms;
        if (age < 0 || age > maxAgeMs) {
          return undefined; // missing or future-dated: treat as absent
        }
        return snapshot;
      } catch {
        return undefined; // Redis down or payload not JSON: fall back
      }
    },
  };
}

/**
 * Adapts a shared snapshot to the shape the existing confluence gate
 * consumes ({@link checkOptionBuyingConfluence} over a `ChainAnalysis`), so
 * shared and local analyses are interchangeable at the gate.
 */
export function sharedChainAnalysis(snapshot: ChainContextSnapshot): {
  readonly spot: number;
  readonly pcr: number;
  readonly atmPcr: number;
  readonly callResistance: OiWall;
  readonly putSupport: OiWall;
  readonly headroomCe: number;
  readonly headroomPe: number;
  readonly bias: 'BULLISH' | 'BEARISH' | 'NEUTRAL';
} {
  return {
    spot: snapshot.spot,
    pcr: snapshot.pcr,
    atmPcr: snapshot.atm_pcr,
    callResistance: { strike: snapshot.call_resistance.strike, oi: snapshot.call_resistance.oi, distance: snapshot.call_resistance.distance },
    putSupport: { strike: snapshot.put_support.strike, oi: snapshot.put_support.oi, distance: snapshot.put_support.distance },
    headroomCe: snapshot.headroom_ce,
    headroomPe: snapshot.headroom_pe,
    bias: snapshot.bias,
  };
}

/**
 * The gate over a shared snapshot. Behaviourally identical to
 * checkOptionBuyingConfluence over a locally computed analysis; kept as a
 * separate function so the shared path has no dependency on the local
 * analyzer's full ChainAnalysis shape.
 */
export function checkSharedChainConfluence(
  analysis: { spot: number; pcr: number; headroomCe: number; headroomPe: number },
  direction: Direction,
  minHeadroomPts = 15,
): { ok: boolean; reason?: string | undefined } {
  if (minHeadroomPts > 0) {
    if (direction === 'BULLISH') {
      if (analysis.headroomCe > 0 && analysis.headroomCe < minHeadroomPts) {
        return { ok: false, reason: `spot ${analysis.spot} is only ${analysis.headroomCe.toFixed(1)} pts below major Call resistance (min headroom: ${minHeadroomPts} pts)` };
      }
    } else if (analysis.headroomPe > 0 && analysis.headroomPe < minHeadroomPts) {
      return { ok: false, reason: `spot ${analysis.spot} is only ${analysis.headroomPe.toFixed(1)} pts above major Put support (min headroom: ${minHeadroomPts} pts)` };
    }
  }

  if (direction === 'BULLISH') {
    if (analysis.pcr < 0.55) {
      return { ok: false, reason: `PCR ${analysis.pcr.toFixed(2)} is severely depressed; heavy call writing overhead` };
    }
    return { ok: true };
  }

  if (analysis.pcr > 1.8) {
    return { ok: false, reason: `PCR ${analysis.pcr.toFixed(2)} is extremely elevated; heavy put writing support` };
  }
  return { ok: true };
}

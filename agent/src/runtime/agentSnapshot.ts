import type { Redis } from 'ioredis';
import { z } from 'zod';
import type { Logger } from '../ops/logger.js';
import type { AgentView, CockpitSnapshot, PositionView } from './views.js';

/**
 * The agent heartbeat (contract `agent-snapshot/1`, vendored at contracts/schemas/agent-snapshot-1.schema.json).
 * algo_scalper_api reads it to show this agent on its dashboard. Display only: nothing in either system trades on
 * it. The 10 s TTL makes a stopped agent disappear, which Rails shows as offline.
 */
export const AGENT_SNAPSHOT_KEY = 'trading:agent:snapshot';
const TTL_SECONDS = 10;
const DEFAULT_INTERVAL_MS = 2_000;
const SNAPSHOT_VERSION = 1;

const positionSchema = z.object({
  option_type: z.enum(['CE', 'PE']),
  quantity_lots: z.number().int().min(1),
  entry_price: z.number(),
  stop_price: z.number().nullable().optional(),
  target_price: z.number().nullable().optional(),
  unrealized_pnl_inr: z.number().nullable().optional(),
}).strict();

export const agentSnapshotSchema = z.object({
  schema: z.literal('agent-snapshot/1'),
  version: z.number().int(),
  mode: z.enum(['paper', 'sandbox', 'live']),
  run_id: z.string(),
  updated_at: z.string(),
  feed_age_ms: z.number().int().nullable(),
  kill_switch: z.object({ engaged: z.boolean(), reason: z.string().nullable().optional() }).strict(),
  day_pnl: z.object({ currency: z.literal('INR'), realized_inr: z.number(), unrealized_inr: z.number() }).strict(),
  entry_window: z.object({ start_minute: z.number().int(), end_minute: z.number().int() }).strict().optional(),
  underlyings: z.array(z.object({
    underlying: z.string(),
    state: z.enum(['IDLE', 'SIGNAL_DETECTED', 'ENTRY_PENDING', 'POSITION_OPEN', 'RISK_MANAGEMENT_ACTIVE', 'EXIT_PENDING', 'POSITION_CLOSED', 'HALTED']),
    position: positionSchema.nullable().optional(),
  }).strict()),
}).strict();

export type AgentSnapshot = z.infer<typeof agentSnapshotSchema>;

function positionOf(view: PositionView): NonNullable<AgentSnapshot['underlyings'][number]['position']> {
  const lots = view.lotSize === undefined || view.lotSize <= 0 ? 1 : Math.max(1, Math.round(view.quantity / view.lotSize));
  return {
    option_type: view.optionType,
    quantity_lots: lots,
    entry_price: view.averagePrice,
    stop_price: view.stopLossPrice,
    target_price: view.targetPrice,
    unrealized_pnl_inr: view.unrealizedInr ?? null,
  };
}

/** One entry per open side, so a simultaneous CE and PE on one underlying both show; one IDLE-style entry otherwise. */
function underlyingEntries(view: AgentView): AgentSnapshot['underlyings'] {
  if (view.positions.length === 0) {
    return [{ underlying: view.symbol, state: view.state, position: null }];
  }
  return view.positions.map((position) => ({ underlying: view.symbol, state: view.state, position: positionOf(position) }));
}

/** The freshest spot tick across underlyings; null before the first tick. */
function feedAgeMs(views: readonly AgentView[]): number | null {
  const ages = views.map((view) => view.spotAgeMs).filter((age): age is number => age !== undefined);
  return ages.length === 0 ? null : Math.round(Math.min(...ages));
}

/** A run that lost the trading lease can no longer enter, so the dashboard shows it as a kill switch. */
export function buildAgentSnapshot(cockpit: CockpitSnapshot, runId: string, nowMs: number, run: { leaseHeld: boolean } = { leaseHeld: true }): AgentSnapshot {
  const reason = cockpit.day.killSwitchReason ?? (run.leaseHeld ? undefined : 'TRADING_LEASE_LOST');
  return {
    schema: 'agent-snapshot/1',
    version: SNAPSHOT_VERSION,
    mode: cockpit.mode,
    run_id: runId,
    updated_at: new Date(nowMs).toISOString(),
    feed_age_ms: feedAgeMs(cockpit.underlyings),
    kill_switch: { engaged: reason !== undefined, reason: reason ?? null },
    day_pnl: { currency: 'INR', realized_inr: cockpit.day.realizedPnlInr, unrealized_inr: cockpit.day.unrealizedPnlInr },
    // Rails reads it to stop forwarding signals the agent would refuse as ENTRY_WINDOW_CLOSED.
    ...(cockpit.entryStartMinute === undefined || cockpit.entryEndMinute === undefined
      ? {}
      : { entry_window: { start_minute: cockpit.entryStartMinute, end_minute: cockpit.entryEndMinute } }),
    underlyings: cockpit.underlyings.flatMap(underlyingEntries),
  };
}

export interface AgentSnapshotOptions {
  readonly redis: Pick<Redis, 'set'>;
  readonly snapshot: () => CockpitSnapshot;
  readonly runId: string;
  readonly logger: Logger;
  readonly leaseHeld?: () => boolean;
  readonly intervalMs?: number;
  readonly now?: () => number;
}

/** Publishes the heartbeat on an unref'd timer. A failed write is logged once per outage and never stops trading. */
export function startAgentSnapshot(options: AgentSnapshotOptions): () => void {
  const now = options.now ?? Date.now;
  let failing = false;
  let inFlight = false;
  const publish = async (): Promise<void> => {
    const leaseHeld = options.leaseHeld?.() ?? true;
    const json = JSON.stringify(buildAgentSnapshot(options.snapshot(), options.runId, now(), { leaseHeld }));
    await options.redis.set(AGENT_SNAPSHOT_KEY, json, 'EX', TTL_SECONDS);
    if (failing) {
      failing = false;
      options.logger.info('agent snapshot publishing again');
    }
  };
  const timer = setInterval(() => {
    if (inFlight) {
      return;
    }
    inFlight = true;
    publish()
      .catch((error: unknown) => {
        if (!failing) {
          failing = true;
          options.logger.warn('agent snapshot not published', { error: error instanceof Error ? error.message : String(error) });
        }
      })
      .finally(() => {
        inFlight = false;
      });
  }, options.intervalMs ?? DEFAULT_INTERVAL_MS);
  timer.unref();
  return () => clearInterval(timer);
}

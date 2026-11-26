import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { AGENT_SNAPSHOT_KEY, agentSnapshotSchema, buildAgentSnapshot, startAgentSnapshot } from '../src/runtime/agentSnapshot.js';
import type { AgentView, CockpitSnapshot, PositionView } from '../src/runtime/views.js';

const NOW = Date.parse('2026-11-25T10:42:11.208+05:30');
const SILENT = { info() {}, warn() {}, error() {} };

function position(overrides: Partial<PositionView> = {}): PositionView {
  return {
    contractSymbol: 'NIFTY-Dec2026-25900-CE', optionType: 'CE', strike: 25900, expiry: '2026-12-01', quantity: 130, lotSize: 65,
    averagePrice: 141.2, stopLossPrice: 120, targetPrice: 211.65, mark: 150, unrealizedInr: 1157, openedAt: NOW - 60_000,
    heldMinutes: 1, exitRequested: false, ...overrides,
  };
}

function agent(symbol: string, overrides: Partial<AgentView> = {}): AgentView {
  return { symbol, state: 'IDLE', halted: undefined, spot: 25_900, spotAgeMs: 900, position: undefined, positions: [], ...overrides } as AgentView;
}

function cockpit(underlyings: AgentView[], killSwitchReason?: string): CockpitSnapshot {
  return {
    at: NOW, mode: 'paper', day: { realizedPnlInr: 4820.5, unrealizedPnlInr: 1157, killSwitchReason }, underlyings,
  } as unknown as CockpitSnapshot;
}

describe('agent-snapshot/1', () => {
  it('should parse the shared contract fixture', () => {
    const fixture = JSON.parse(readFileSync('contracts/fixtures/agent-snapshot-1.example.json', 'utf8'));
    assert.equal(agentSnapshotSchema.safeParse(fixture).success, true);
  });

  it('should map the cockpit view to a contract-valid snapshot', () => {
    const snapshot = buildAgentSnapshot(cockpit([agent('NIFTY', { state: 'RISK_MANAGEMENT_ACTIVE', positions: [position()] }), agent('SENSEX', { spotAgeMs: 400 })]), 'run-1', NOW);

    assert.equal(agentSnapshotSchema.safeParse(snapshot).success, true);
    assert.equal(snapshot.feed_age_ms, 400);
    assert.deepEqual(snapshot.kill_switch, { engaged: false, reason: null });
    assert.deepEqual(snapshot.underlyings[0], {
      underlying: 'NIFTY',
      state: 'RISK_MANAGEMENT_ACTIVE',
      position: { option_type: 'CE', quantity_lots: 2, entry_price: 141.2, stop_price: 120, target_price: 211.65, unrealized_pnl_inr: 1157 },
    });
    assert.deepEqual(snapshot.underlyings[1], { underlying: 'SENSEX', state: 'IDLE', position: null });
  });

  it('should list each open side of an underlying as its own entry', () => {
    const both = [position(), position({ optionType: 'PE', contractSymbol: 'NIFTY-Dec2026-25900-PE' })];
    const snapshot = buildAgentSnapshot(cockpit([agent('NIFTY', { state: 'RISK_MANAGEMENT_ACTIVE', positions: both })]), 'run-1', NOW);

    assert.deepEqual(snapshot.underlyings.map((u) => u.position?.option_type), ['CE', 'PE']);
  });

  it('should report an engaged kill switch and a missing feed as null', () => {
    const snapshot = buildAgentSnapshot(cockpit([agent('NIFTY', { spotAgeMs: undefined })], 'DAILY_LOSS_BREACH'), 'run-1', NOW);

    assert.deepEqual(snapshot.kill_switch, { engaged: true, reason: 'DAILY_LOSS_BREACH' });
    assert.equal(snapshot.feed_age_ms, null);
  });

  it('should publish the entry window so Rails stops forwarding outside it', () => {
    const view = { ...cockpit([agent('NIFTY')]), entryStartMinute: 570, entryEndMinute: 840 } as CockpitSnapshot;

    assert.deepEqual(buildAgentSnapshot(view, 'run-1', NOW).entry_window, { start_minute: 570, end_minute: 840 });
  });

  it('should report a lost trading lease as an engaged kill switch', () => {
    const snapshot = buildAgentSnapshot(cockpit([agent('NIFTY')]), 'run-1', NOW, { leaseHeld: false });

    assert.deepEqual(snapshot.kill_switch, { engaged: true, reason: 'TRADING_LEASE_LOST' });
  });

  it('should publish with a TTL and keep running when Redis fails', async () => {
    const writes: unknown[][] = [];
    let fail = true;
    const redis = {
      set: async (...args: unknown[]) => {
        writes.push(args);
        if (fail) {
          fail = false;
          throw new Error('redis down');
        }
        return 'OK' as const;
      },
    };
    const stop = startAgentSnapshot({ redis, snapshot: () => cockpit([agent('NIFTY')]), runId: 'run-1', logger: SILENT, intervalMs: 5, now: () => NOW });
    await new Promise((resolve) => setTimeout(resolve, 40));
    stop();

    assert.ok(writes.length >= 2, 'a failed write does not stop the heartbeat');
    const [key, json, ex, ttl] = writes.at(-1)!;
    assert.deepEqual([key, ex, ttl], [AGENT_SNAPSHOT_KEY, 'EX', 10]);
    assert.equal(JSON.parse(json as string).run_id, 'run-1');
  });
});

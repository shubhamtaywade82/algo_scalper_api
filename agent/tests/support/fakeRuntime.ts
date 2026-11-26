import { loadConfig } from '../../src/config.js';
import type { Candle, InstrumentRef, Tick, UnderlyingSpec } from '../../src/domain/types.js';
import type { EventLog } from '../../src/ops/eventLog.js';
import { RingLogger } from '../../src/ops/logger.js';
import { PaperExecutionPort } from '../../src/execution/paper.js';
import type { Runtime } from '../../src/runtime/createRuntime.js';
import { Orchestrator, type OrchestratorFeed } from '../../src/runtime/orchestrator.js';

/** A feed that never delivers ticks. Enough to drive the cockpit without any market data. */
export class QuietFeed implements OrchestratorFeed {
  async start(): Promise<void> {
    return;
  }
  stop(): void {
    return;
  }
  onTick(_listener: (tick: Tick) => void): () => void {
    return () => undefined;
  }
  subscribe(_refs: readonly InstrumentRef[]): void {
    return;
  }
  unsubscribe(_refs: readonly InstrumentRef[]): void {
    return;
  }
  ageMs(): number | undefined {
    return 100;
  }
}

export const FAKE_SPEC: UnderlyingSpec = {
  symbol: 'NIFTY',
  spot: { exchangeSegment: 'IDX_I', securityId: '13' },
  optionSegment: 'NSE_FNO',
};

/** Orchestrator wired to fakes: paper venue, no market data, no network. For cockpit tests and the offline demo. */
export function fakeRuntime(nowEpochMs = Date.parse('2026-10-12T04:30:00Z')): { runtime: Runtime; stop: () => Promise<void> } {
  const records = new RingLogger(200);
  const market = {
    intradayCandles: async (): Promise<Candle[]> => [],
    listExpiries: async (): Promise<string[]> => [],
    optionChain: async () => ({ expiry: '2026-10-15', fetchedAt: nowEpochMs, strikes: [] }),
    optionContracts: async () => [],
    availableFunds: async () => 300_000,
    brokerOpenOptionCount: async () => 0,
    brokerLiveOrderCount: async () => 0,
  };
  const events = {
    record: () => undefined,
    durable: async () => undefined,
    unconfirmedEvents: () => 0,
    flush: async () => undefined,
  } as unknown as EventLog;
  const config = loadConfig({ DHAN_CLIENT_ID: '1', DHAN_ACCESS_TOKEN: 't', DATABASE_URL: 'postgres://paper.test.invalid/agent' });
  const orchestrator = new Orchestrator(config, [FAKE_SPEC], {
    market,
    feed: new QuietFeed(),
    execution: new PaperExecutionPort({ slippageBps: 0 }),
    advisor: undefined,
    events,
    logger: records,
    clockIntervalMs: 1e9,
    shutdownTimeoutMs: 1_000,
    now: () => nowEpochMs,
  });
  return { runtime: { orchestrator, logger: records, records }, stop: () => orchestrator.stop() };
}

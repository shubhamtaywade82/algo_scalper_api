import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { loadConfig, type AgentConfig } from '../src/config.js';
import type { Candle, InstrumentRef, OptionContract, Tick, UnderlyingSpec } from '../src/domain/types.js';
import type { EntryOrder, ExecutionEvent, ExecutionPort, ExitOrder } from '../src/execution/ports.js';
import { PaperExecutionPort } from '../src/execution/paper.js';
import type { AdvisoryVerdict, TradeAdvisor } from '../src/llm/advisor.js';
import type { EventLog } from '../src/ops/eventLog.js';
import type { Logger } from '../src/ops/logger.js';
import { Orchestrator, type OrchestratorFeed } from '../src/runtime/orchestrator.js';
import type { DiscoveredOpenPosition } from '../src/runtime/ports.js';
import { ledgerAndLeaseGate, type TradingGate } from '../src/runtime/tradingGate.js';
import type { ChainSnapshot } from '../src/options/selector.js';
import { bar, contract, istEpoch, SESSION_DAY } from './support/fixtures.js';

const SILENT: Logger = { info() {}, warn() {}, error() {} };
const SPOT: InstrumentRef = { exchangeSegment: 'IDX_I', securityId: '13' };
// Synthetic index levels around 100 keep the fixtures readable; the strike step is 1 point.
const CE: OptionContract = contract({ optionType: 'CE', strike: 101, securityId: '48001', expiry: '2026-10-15', lotSize: 75, tickSize: 0.05 });
const PE: OptionContract = contract({ optionType: 'PE', strike: 101, securityId: '48002', expiry: '2026-10-15', lotSize: 75, tickSize: 0.05 });
const SPEC: UnderlyingSpec = { symbol: 'NIFTY', spot: SPOT, optionSegment: 'NSE_FNO' };

function hhmm(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

/** Previous session rising 90 → 100: establishes an UP SuperTrend before today's open. */
function previousDay(): Candle[] {
  return Array.from({ length: 60 }, (_, i) => {
    const close = 90 + (i * 10) / 59;
    return bar(istEpoch('2026-10-09', hhmm(9 * 60 + 15 + i * 5)), close, close + 0.5, close - 0.5, close);
  });
}

/** Today's history through the 09:35 bar: opening range around 100, last close 100.3. */
function todayHistory(): Candle[] {
  const closes = [100, 100, 100, 100, 100.3];
  return closes.map((close, i) => bar(istEpoch(SESSION_DAY, hhmm(9 * 60 + 15 + i * 5)), close, close + 0.5, close - 0.5, close));
}

interface Harness {
  readonly orchestrator: Orchestrator;
  readonly feed: FakeFeed;
  readonly events: { type: string; payload: Record<string, unknown> }[];
  readonly setClock: (hhmmValue: string, day?: string) => void;
  readonly now: () => number;
  readonly paperCloses: ExitOrder[];
}

class FakeFeed implements OrchestratorFeed {
  readonly subscribed = new Set<string>();
  age: number | undefined = 100;
  /** Set to a terminal disconnect code to simulate the server ending the market feed. */
  terminal: number | undefined = undefined;
  terminalDisconnectCode(): number | undefined {
    return this.terminal;
  }
  startCalled = false;
  private readonly listeners = new Set<(tick: Tick) => void>();
  constructor(private readonly startGate?: Promise<void>) {}
  async start(): Promise<void> {
    this.startCalled = true;
    await this.startGate;
  }
  stop(): void {
    this.listeners.clear();
  }
  onTick(listener: (tick: Tick) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
  subscribe(refs: readonly InstrumentRef[]): void {
    for (const ref of refs) {
      this.subscribed.add(`${ref.exchangeSegment}:${ref.securityId}`);
    }
  }
  unsubscribe(refs: readonly InstrumentRef[]): void {
    for (const ref of refs) {
      this.subscribed.delete(`${ref.exchangeSegment}:${ref.securityId}`);
    }
  }
  ageMs(): number | undefined {
    return this.age;
  }
  emit(tick: Tick): void {
    for (const listener of this.listeners) {
      listener(tick);
    }
  }
}

function chain(now: () => number): ChainSnapshot {
  const leg = (securityId: string, bid: number, ask: number) => ({
    ltp: (bid + ask) / 2,
    bid,
    ask,
    oi: 500_000,
    volume: 10_000,
    securityId,
  });
  return {
    expiry: '2026-10-15',
    fetchedAt: now(),
    strikes: [
      { strike: 100, call: leg('48003', 102, 102.5), put: leg('48004', 0.8, 1) },
      { strike: 101, call: leg('48001', 100.5, 101), put: leg('48002', 100.5, 101) },
      { strike: 102, call: leg('48005', 0.8, 1), put: leg('48006', 102, 102.5) },
    ],
  };
}

function build(
  env: Record<string, string> = {},
  options: {
    advisor?: TradeAdvisor;
    execution?: ExecutionPort;
    brokerOpen?: number;
    brokerOpenPositions?: readonly DiscoveredOpenPosition[];
    expiriesGate?: Promise<void>;
    feedGate?: Promise<void>;
    /** When set, the paper venue records each broker kill-switch engagement here. */
    killSwitch?: string[];
    /** Controls durable writes. Each call is recorded, and the returned promise decides whether it succeeds. */
    durable?: (type: string) => Promise<void>;
    gate?: TradingGate;
    brokerLiveOrders?: number;
    /** Broker available funds. Defaults to CAPITAL_INR. */
    funds?: number;
    /** Runs inside the funds call, the last REST call before the risk gate. */
    onFunds?: () => void;
    openingCapitalInr?: number;
    /** Makes the paper venue report the protection an exchange-held bracket gives. */
    exchangeHeld?: boolean;
    /** Records each arm of the broker P&L exit, as the live venue would receive it. */
    brokerPnlExitArm?: number[];
  } = {},
): Harness {
  // Start after the warmup's last bar has closed; the clock guard refuses bars stamped in the future.
  let clock = istEpoch(SESSION_DAY, '09:50');
  const now = () => clock;
  const config: AgentConfig = loadConfig({
    DHAN_CLIENT_ID: '1',
    DHAN_ACCESS_TOKEN: 't',
    DATABASE_URL: 'postgres://paper.test.invalid/agent',
    CAPITAL_INR: '300000',
    MAX_RISK_PER_TRADE_PCT: '1',
    MAX_DAILY_LOSS_PCT: '1',
    // Fixture prices assume the entry is priced at the ask; one test below covers the buffer.
    ENTRY_LIMIT_BUFFER_PCT: '0',
    ...env,
  });
  const feed = new FakeFeed(options.feedGate);
  const events: Harness['events'] = [];
  const paperCloses: ExitOrder[] = [];
  const paper = new PaperExecutionPort({ slippageBps: 0, now });
  if (options.exchangeHeld === true) {
    Object.assign(paper, { protection: 'EXCHANGE_BRACKET' });
  }
  if (options.brokerPnlExitArm !== undefined) {
    const armed = options.brokerPnlExitArm;
    Object.assign(paper, { armBrokerPnlExit: async (lossInr: number) => void armed.push(lossInr) });
  }
  const execution = options.execution ?? paper;
  if (execution === paper) {
    paper.onEvent(() => undefined);
    if (options.killSwitch !== undefined) {
      const engaged = options.killSwitch;
      Object.assign(paper, { engageBrokerKillSwitch: async (reason: string) => void engaged.push(reason) });
    }
  }
  const market = {
    intradayCandles: async () => [...previousDay(), ...todayHistory()],
    listExpiries: async () => {
      await options.expiriesGate;
      return ['2026-10-15'];
    },
    optionChain: async () => chain(now),
    optionContracts: async () => [CE, PE],
    availableFunds: async () => {
      options.onFunds?.();
      return options.funds ?? 300_000;
    },
    brokerOpenOptionCount: async () => options.brokerOpen ?? 0,
    ...(options.brokerOpenPositions !== undefined ? { brokerOpenPositions: async () => options.brokerOpenPositions! } : {}),
    brokerLiveOrderCount: async () => options.brokerLiveOrders ?? 0,
  };
  const eventLog = {
    record: (type: string, payload: Record<string, unknown>) => {
      events.push({ type, payload });
    },
    // Durable writes land in the same list. The harness has no journal file or ledger to fail.
    durable: async (type: string, payload: Record<string, unknown>) => {
      events.push({ type, payload });
      await (options.durable ?? (async () => undefined))(type);
    },
    unconfirmedEvents: () => 0,
    flush: async () => undefined,
  } as unknown as EventLog;
  const orchestrator = new Orchestrator(config, [SPEC], {
    market,
    feed,
    execution,
    advisor: options.advisor,
    events: eventLog,
    logger: SILENT,
    now,
    clockIntervalMs: 1e9,
    shutdownTimeoutMs: 2_000,
    ...(options.gate === undefined ? {} : { gate: options.gate }),
    ...(options.openingCapitalInr === undefined ? {} : { openingCapitalInr: options.openingCapitalInr }),
  });
  return {
    orchestrator,
    feed,
    events,
    paperCloses,
    setClock: (value, day = SESSION_DAY) => {
      clock = istEpoch(day, value);
    },
    now,
  };
}

async function settle(orchestrator: Orchestrator): Promise<void> {
  for (let i = 0; i < 5; i += 1) {
    await new Promise<void>((resolve) => setImmediate(resolve));
    await orchestrator.agent('NIFTY')?.drain();
  }
}

function clockTick(orchestrator: Orchestrator): void {
  (orchestrator as unknown as { onClock(): void }).onClock();
}

function spotTick(harness: Harness, ltp: number, at: string): void {
  harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp, ltt: istEpoch(SESSION_DAY, at) });
}

function optionTick(harness: Harness, securityId: string, ltp: number): void {
  harness.feed.emit({ exchangeSegment: 'NSE_FNO', securityId, ltp, ltt: istEpoch(SESSION_DAY, '10:00') });
}

/** Drives the breakout: 09:40 bar closes at 101.5 after the 09:35 bar closed at 100.3. */
async function triggerBreakout(harness: Harness): Promise<void> {
  harness.setClock('09:40:10');
  spotTick(harness, 101.5, '09:40:10');
  harness.setClock('09:45:05');
  spotTick(harness, 101.6, '09:45:05');
  await settle(harness.orchestrator);
}

function types(harness: Harness): string[] {
  return harness.events.map((event) => event.type);
}

describe('runtime: cockpit view updates', () => {
  it('notifies listeners on each routed spot tick with the latest LTP', async () => {
    const harness = build();
    await harness.orchestrator.start();
    let views = 0;
    harness.orchestrator.onViewUpdate(() => {
      views += 1;
    });
    spotTick(harness, 22_512.5, '10:01:00');
    assert.equal(views, 1);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.spot, 22_512.5);
    spotTick(harness, 22_513.0, '10:01:01');
    assert.equal(views, 2);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.spot, 22_513);
  });
});

describe('runtime: winning trade end to end (paper venue)', () => {
  it('detects the breakout, buys one ATM call, and closes it at the bracket target', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);

    const agent = harness.orchestrator.agent('NIFTY');
    assert.equal(agent?.state, 'RISK_MANAGEMENT_ACTIVE');
    const position = agent?.openPosition;
    assert.equal(position?.contract.securityId, '48001');
    assert.equal(position?.quantity, 75);
    assert.equal(position?.averagePrice, 101);
    assert.equal(position?.stopLossPrice, 70.7);
    assert.equal(position?.targetPrice, 161.6);

    harness.setClock('10:00:00');
    optionTick(harness, '48001', 161.7);
    await settle(harness.orchestrator);

    assert.equal(agent?.state, 'IDLE');
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'TARGET');
    // Gross 75 × (161.6 − 101) = 4545. Charges: brokerage 40 + exchange 6.90 + SEBI 0.02 + STT 18.18
    // + stamp 0.23 + GST 8.45 = 73.77.
    assert.equal(closed?.payload['grossPnlInr'], 4545);
    assert.equal(closed?.payload['chargesInr'], 73.77);
    assert.equal(closed?.payload['pnlInr'], 4471.23);
    const snapshot = harness.orchestrator.dayBook.snapshot();
    assert.equal(snapshot.tradesToday, 1);
    assert.equal(snapshot.dayPnlInr, 4471.23, 'the day book carries the net figure');
    assert.deepEqual(snapshot.openUnderlyings, []);
    assert.ok(types(harness).includes('entry_submitted'));
    assert.ok(types(harness).includes('entry_filled'));
  });

  it('trails stop loss to breakeven at 1R and steps up with gains in runner mode', async () => {
    const harness = build({
      TRAILING_JUMP_PCT: '15',
      BREAKEVEN_AT_RR: '1',
      RUNNER_MODE: 'true',
    });
    await harness.orchestrator.start();
    await triggerBreakout(harness);

    const agent = harness.orchestrator.agent('NIFTY');
    assert.equal(agent?.state, 'RISK_MANAGEMENT_ACTIVE');
    assert.equal(agent?.openPosition?.averagePrice, 101);
    assert.equal(agent?.openPosition?.stopLossPrice, 70.7);

    // Tick below 1R (101 + 30.3 = 131.3): stop remains at initial 70.7
    optionTick(harness, '48001', 125);
    await settle(harness.orchestrator);
    assert.equal(agent?.openPosition?.stopLossPrice, 70.7);

    // Tick reaches 1R: stop jumps to breakeven 101
    optionTick(harness, '48001', 132);
    await settle(harness.orchestrator);
    assert.equal(agent?.openPosition?.stopLossPrice, 101);

    // Tick reaches 1R + 1 jump (131.3 + 15.15 = 146.45): stop jumps to 101 + 15.15 = 116.15
    optionTick(harness, '48001', 150);
    await settle(harness.orchestrator);
    assert.equal(agent?.openPosition?.stopLossPrice, 116.15);

    // In runner mode, a tick at the original 2R target (161.7) does not exit
    optionTick(harness, '48001', 161.7);
    await settle(harness.orchestrator);
    assert.equal(agent?.state, 'RISK_MANAGEMENT_ACTIVE');

    // Price pulls back to 116.15: hits trailed stop, fills at 116.15 with profit
    harness.setClock('10:05:00');
    optionTick(harness, '48001', 116.15);
    await settle(harness.orchestrator);

    assert.equal(agent?.state, 'IDLE');
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'STOP_LOSS');
    assert.equal(closed?.payload['exitPrice'], 116.15);
    assert.ok(Number(closed?.payload['pnlInr']) > 0, 'trailed stop locked in net profit');
  });

  it('should not deduct charges again when the venue nets them into its fill prices', async () => {
    const paper = Object.assign(new PaperExecutionPort({ slippageBps: 0 }), { chargesInFills: true });
    const harness = build({}, { execution: paper });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    harness.setClock('10:00:00');
    optionTick(harness, '48001', 161.7);
    await settle(harness.orchestrator);
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['chargesInr'], 0);
    assert.equal(closed?.payload['pnlInr'], 4545);
  });

  it('should journal the setup behind each entry for the performance report', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const entry = harness.events.find((event) => event.type === 'entry_submitted')?.payload;
    assert.equal(entry?.['strategy'], 'range');
    assert.equal(entry?.['posture'], 'aligned');
    assert.equal(entry?.['direction'], 'BULLISH');
    assert.equal(entry?.['optionType'], 'CE');
    assert.equal(entry?.['expiry'], '2026-10-15');
    assert.equal(typeof entry?.['daysToExpiry'], 'number');
    assert.equal(typeof entry?.['minuteOfDayIst'], 'number');
  });

  it('flattens an open position at the end-of-day cutoff', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    harness.setClock('15:05:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'EOD_FLATTEN');
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'IDLE');
  });

  it('closes at the stop, fills at the gapped price, and trips the daily-loss kill switch', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    harness.setClock('10:05:00');
    optionTick(harness, '48001', 15);
    await settle(harness.orchestrator);
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);

    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'STOP_LOSS');
    assert.equal(closed?.payload['exitPrice'], 15, 'a gap through the stop fills at the market, not at the stop');
    assert.equal(closed?.payload['grossPnlInr'], -6450);
    assert.equal(closed?.payload['pnlInr'], -6502.72);
    assert.ok(harness.orchestrator.dayBook.snapshot().killSwitchReason?.startsWith('daily loss'));

    // A fresh, valid breakout after the breach must be detected and then refused by the kill switch.
    harness.setClock('11:00:10');
    spotTick(harness, 100.2, '11:00:10');
    harness.setClock('11:05:05');
    spotTick(harness, 101.6, '11:05:05');
    harness.setClock('11:10:05');
    spotTick(harness, 101.7, '11:10:05');
    await settle(harness.orchestrator);
    const refused = harness.events.filter((event) => event.type === 'signal_dropped');
    assert.equal(refused.at(-1)?.payload['code'], 'KILL_SWITCH_ACTIVE');
    assert.equal(harness.events.filter((event) => event.type === 'entry_submitted').length, 1, 'no second entry after the breach');
  });
});

describe('runtime: carried balance', () => {
  it('should show the balance carried from earlier sessions, not CAPITAL_INR, when an opening balance is given', () => {
    const snapshot = build({}, { openingCapitalInr: 312_345.5 }).orchestrator.snapshot();
    assert.equal(snapshot.initialCapitalInr, 300_000);
    assert.equal(snapshot.currentBalanceInr, 312_345.5);
    assert.equal(snapshot.realTimeBalanceInr, 312_345.5);
    const atCapital = build().orchestrator.snapshot();
    assert.ok(Math.abs(snapshot.dailyLossLimitInr - (atCapital.dailyLossLimitInr * 312_345.5) / 300_000) < 1e-6, 'the loss limit follows the capital');
  });
});

describe('runtime: market context', () => {
  it('should take a with-trend breakout through the context gate and show the context', async () => {
    // The warmup climbs all session, so the day, the structure and the regime all back a bullish entry.
    const harness = build({ CONTEXT_FILTER_ENABLED: 'true' });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), true);
    assert.equal(harness.events.some((event) => event.payload['code'] === 'CONTEXT_REJECTED'), false);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.context?.structure.trend, 'BULLISH');
  });
});

describe('runtime: risk capital', () => {
  // One lot risks (101 - 70.7) × 75 = 2272.5. CAPITAL_INR 300000 at 1% allows 3000, so one lot.
  it('should size from CAPITAL_INR when the broker balance is larger', async () => {
    const harness = build({ MAX_LOTS_PER_ORDER: '50' }, { funds: 10_000_000 });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.openPosition?.quantity, 75);
  });

  it('should price, size and bracket the entry off the buffered limit, not the bare ask', async () => {
    const entries: EntryOrder[] = [];
    const paper = new PaperExecutionPort({ slippageBps: 0 });
    const execution: ExecutionPort = Object.assign(Object.create(paper) as ExecutionPort, {
      submitEntry: async (order: EntryOrder) => {
        entries.push(order);
      },
    });
    const harness = build({ ENTRY_LIMIT_BUFFER_PCT: '1' }, { execution });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    // Ask 101 × 1.01 = 102.01, rounded up to the 0.05 tick. Stop 102.05 × 0.7 = 71.435 → 71.45.
    assert.equal(entries[0]?.entryReference, 102.05);
    assert.equal(entries[0]?.stopLossPrice, 71.45);
    assert.equal(entries[0]?.targetPrice, 163.25);
  });

  it('should compound: size off the opening capital, not CAPITAL_INR', async () => {
    // 1% of 700000 is 7000, which covers three lots at 2272.5.
    const harness = build({ MAX_LOTS_PER_ORDER: '50' }, { funds: 10_000_000, openingCapitalInr: 700_000 });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.openPosition?.quantity, 225);
  });

  it('should not shrink the risk budget because cash is tied up in open premium', async () => {
    // 20000 cash buys two lots at 7575; risk still comes from the 300000 capital, so one lot, not none.
    const harness = build({ MAX_LOTS_PER_ORDER: '50' }, { funds: 20_000 });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.openPosition?.quantity, 75);
  });

  it('should shrink the risk budget when the opening capital is below CAPITAL_INR', async () => {
    const harness = build({ MAX_LOTS_PER_ORDER: '50' }, { openingCapitalInr: 150_000 });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const dropped = harness.events.find((event) => event.type === 'signal_dropped');
    assert.equal(dropped?.payload['code'], 'RISK_BUDGET_TOO_SMALL');
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
  });
});

describe('runtime: freshness at the gate and at submit', () => {
  it('should count the time spent on REST calls in the option quote age', async () => {
    let advance = (): void => undefined;
    const harness = build({}, { onFunds: () => advance() });
    advance = () => harness.setClock('09:45:11');
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    // The chain was read at 09:45:05 and the gate ran at 09:45:11: 6 s old against FEED_STALE_MS 5 s.
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'OPTION_QUOTE_STALE');
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
  });

  it('should drop the entry when the spot feed goes stale during the advisor review', async () => {
    let harness: Harness | undefined;
    const advisor: TradeAdvisor = {
      review: async () => {
        harness!.feed.age = 9_000;
        return { decision: 'ENTER', confidence: 0.9, reason: 'ok', source: 'llm' } as AdvisoryVerdict;
      },
    };
    harness = build({}, { advisor });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const dropped = harness.events.find((event) => event.type === 'signal_dropped');
    assert.equal(dropped?.payload['code'], 'STALE_AT_SUBMIT');
    assert.match(String(dropped?.payload['detail']), /spot tick age 9000/);
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
  });

  it('should drop the entry when the advisor review runs past the entry window', async () => {
    let harness: Harness | undefined;
    const advisor: TradeAdvisor = {
      review: async () => {
        harness!.setClock('14:30:01');
        return { decision: 'ENTER', confidence: 0.9, reason: 'ok', source: 'llm' } as AdvisoryVerdict;
      },
    };
    harness = build({}, { advisor });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'STALE_AT_SUBMIT');
  });
});

describe('runtime: entry preparation and exits', () => {
  // Bounded: before the fix the queue waited on the preparation, so this test hung instead of failing.
  it('should exit one side while an entry on the other side is still being prepared', { timeout: 5_000 }, async () => {
    const options: Parameters<typeof build>[1] = {};
    const harness = build({ MAX_OPEN_POSITIONS: '2' }, options);
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const agent = harness.orchestrator.agent('NIFTY');
    assert.equal(agent?.openPositions[0]?.contract.optionType, 'CE');

    let releaseChain = (): void => undefined;
    options.expiriesGate = new Promise<void>((resolve) => {
      releaseChain = resolve;
    });
    harness.setClock('15:04:50');
    assert.match(harness.orchestrator.triggerTestTrade('NIFTY', 'BEARISH'), /test BEARISH signal/);
    await settle(harness.orchestrator);

    harness.setClock('15:05:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'EOD_FLATTEN', 'the CE exit is not queued behind the PE preparation');
    assert.equal(closed?.payload['optionType'], 'CE');

    releaseChain();
    await settle(harness.orchestrator);
    assert.equal(agent?.isFlat(), true, 'the late PE entry is refused, not left pending');
    assert.equal(harness.events.filter((event) => event.type === 'entry_submitted').length, 1);
  });
});

describe('runtime: vetoes', () => {
  it('lets an advisor SKIP stop the entry without any order being sent', async () => {
    const advisor: TradeAdvisor = {
      review: async () => ({ decision: 'SKIP', confidence: 0.9, reason: 'spot stretched', source: 'llm' }) as AdvisoryVerdict,
    };
    const harness = build({}, { advisor });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'IDLE');
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'ADVISOR_SKIP');
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
  });

  it('refuses entries on stale spot data', async () => {
    const harness = build();
    harness.feed.age = 60_000;
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'SPOT_DATA_STALE');
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
  });

  it('refuses to start while the broker already holds option positions', async () => {
    const harness = build({}, { brokerOpen: 1 });
    await assert.rejects(harness.orchestrator.start(), /open option position/);
  });

  it('refuses to start while the broker holds a live order with no position yet', async () => {
    // An entry accepted just before a crash has no position yet, so only the order book can show it.
    const harness = build({}, { brokerLiveOrders: 1 });
    await assert.rejects(harness.orchestrator.start(), /not in a terminal status/);
  });

  it('adopts open option positions on startup and activates risk management', async () => {
    const position: DiscoveredOpenPosition = {
      positionId: 'recovered-1',
      underlying: 'NIFTY',
      securityId: CE.securityId,
      exchangeSegment: CE.exchangeSegment,
      quantity: 75,
      averagePrice: 120,
      stopLossPrice: 96,
      targetPrice: 168,
      openedAt: istEpoch(SESSION_DAY, '09:30'),
    };
    const harness = build({}, { brokerOpen: 1, brokerOpenPositions: [position] });
    await harness.orchestrator.start();
    assert.equal(harness.orchestrator.snapshot().phase, 'RUNNING');
    const agent = harness.orchestrator.agent('NIFTY');
    assert.equal(agent?.state, 'RISK_MANAGEMENT_ACTIVE');
    assert.equal(agent?.openPositions.length, 1);
    assert.equal(agent?.openPositions[0]?.positionId, 'recovered-1');
    assert.equal(agent?.openPositions[0]?.contract.symbol, CE.symbol);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.positions.length, 1);
    assert.equal(harness.orchestrator.snapshot().day.openPositions, 1);
  });
});

/** Live-like venue: every entry comes back UNCONFIRMED, and `lateFill` then fills it, as reconciliation would. */
function scriptedVenue(script: { exit: 'FILL' | 'UNCONFIRMED' }) {
  const killSwitch: string[] = [];
  const exits: ExitOrder[] = [];
  let lastEntry: EntryOrder | undefined;
  let listener: ((event: ExecutionEvent) => void) | undefined;
  const emit = (event: ExecutionEvent) => queueMicrotask(() => listener?.(event));
  const port: ExecutionPort = {
    mode: 'live',
    protection: 'EXCHANGE_BRACKET',
    submitEntry: async (order) => {
      lastEntry = order;
      emit({ kind: 'ENTRY_UNCONFIRMED', correlationId: order.correlationId, underlying: 'NIFTY', reason: 'timeout' });
    },
    submitExit: async (order) => {
      exits.push(order);
      const base = { correlationId: order.correlationId, underlying: 'NIFTY', positionId: order.positionId };
      emit(
        script.exit === 'FILL'
          ? { kind: 'EXIT_FILLED', ...base, quantity: order.quantity, averagePrice: 90, reason: order.reason, at: 0 }
          : { kind: 'EXIT_UNCONFIRMED', ...base, reason: 'timeout' },
      );
    },
    onOptionTick: () => undefined,
    onEvent: (fn) => {
      listener = fn;
      return () => undefined;
    },
    engageBrokerKillSwitch: async (reason) => {
      killSwitch.push(reason);
    },
    close: async () => undefined,
  };
  const lateFill = (quantity: number, averagePrice: number): void => {
    const correlationId = lastEntry?.correlationId ?? 'missing';
    emit({ kind: 'ENTRY_FILLED', correlationId, underlying: 'NIFTY', quantity, averagePrice, at: 0 });
  };
  return { port, killSwitch, exits, lateFill };
}

describe('runtime: open risk under a broker-held trailing stop', () => {
  function fillingVenue(mode: 'live' | 'paper'): ExecutionPort {
    let listener: ((event: ExecutionEvent) => void) | undefined;
    return {
      mode,
      protection: mode === 'live' ? 'EXCHANGE_BRACKET' : 'CLIENT_SIDE',
      submitEntry: async (order) => {
        queueMicrotask(() =>
          listener?.({ kind: 'ENTRY_FILLED', correlationId: order.correlationId, underlying: 'NIFTY', quantity: order.quantity, averagePrice: order.entryReference, at: 0 }),
        );
      },
      submitExit: async () => undefined,
      onOptionTick: () => undefined,
      onEvent: (fn) => {
        listener = fn;
        return () => undefined;
      },
      engageBrokerKillSwitch: async () => undefined,
      close: async () => undefined,
    };
  }

  it('should keep day-book open risk at the initial stop when the live broker holds the stop', async () => {
    const harness = build({ TRAILING_JUMP_PCT: '15', BREAKEVEN_AT_RR: '1' }, { execution: fillingVenue('live') });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const agent = harness.orchestrator.agent('NIFTY');
    assert.equal(agent?.state, 'RISK_MANAGEMENT_ACTIVE');
    const before = harness.orchestrator.dayBook.snapshot().openRiskInr;
    assert.ok(before > 0);

    optionTick(harness, '48001', 132);
    await settle(harness.orchestrator);
    assert.equal(agent?.openPosition?.stopLossPrice, 101, 'the local estimate still trails, for the cockpit');
    assert.equal(harness.orchestrator.dayBook.snapshot().openRiskInr, before, "the broker's trailing stop is not the agent's model, so risk is not released on it");
  });

  it('should lower open risk with the stop on a venue that enforces the agent model', async () => {
    const harness = build({ TRAILING_JUMP_PCT: '15', BREAKEVEN_AT_RR: '1', RUNNER_MODE: 'true' });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    const before = harness.orchestrator.dayBook.snapshot().openRiskInr;
    optionTick(harness, '48001', 132);
    await settle(harness.orchestrator);
    assert.ok(harness.orchestrator.dayBook.snapshot().openRiskInr < before);
  });
});

describe('runtime: exchange freeze quantity', () => {
  const MULTI_LOT = { MAX_RISK_PER_TRADE_PCT: '3', MAX_DAILY_LOSS_PCT: '3', MAX_LOTS_PER_ORDER: '10' };

  async function enteredQuantity(env: Record<string, string>): Promise<number | undefined> {
    const harness = build({ ...MULTI_LOT, ...env });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    return harness.orchestrator.agent('NIFTY')?.openPosition?.quantity;
  }

  it('should size an entry at or below the freeze quantity, in whole lots', async () => {
    const lotSize = CE.lotSize;
    const uncapped = await enteredQuantity({});
    assert.ok(uncapped !== undefined && uncapped >= 3 * lotSize, 'the fixture sizes three lots or more without a freeze quantity');
    // One unit short of three lots: two whole lots fit.
    assert.equal(await enteredQuantity({ FREEZE_QTY_NIFTY: String(3 * lotSize - 1) }), 2 * lotSize);
  });

  it('should take no entry when the freeze quantity is below one lot', async () => {
    assert.equal(await enteredQuantity({ FREEZE_QTY_NIFTY: String(CE.lotSize - 1) }), undefined);
  });
});

describe('runtime: market feed ended by the server', () => {
  it('refuses a new entry after a terminal feed disconnect, and names the code in the signal drop', async () => {
    const harness = build();
    await harness.orchestrator.start();
    harness.feed.terminal = 806;
    await triggerBreakout(harness);
    assert.ok(!types(harness).includes('entry_submitted'), 'no order may follow a dead feed');
    const dropped = harness.events.find((event) => event.type === 'signal_dropped');
    assert.equal(dropped?.payload['code'], 'ENTRY_BLOCKED');
    assert.match(String(dropped?.payload['detail']), /market feed ended by the server with code 806/);
  });
});

describe('runtime: halts', () => {
  it('halts the underlying on an unconfirmed entry and engages the broker kill switch at once when nothing is open', async () => {
    const killSwitch: string[] = [];
    const entries: EntryOrder[] = [];
    let listener: ((event: ExecutionEvent) => void) | undefined;
    const execution: ExecutionPort = {
      mode: 'live',
      protection: 'EXCHANGE_BRACKET',
      submitEntry: async (order) => {
        entries.push(order);
        listener?.({ kind: 'ENTRY_UNCONFIRMED', correlationId: order.correlationId, underlying: 'NIFTY', reason: 'timeout' });
      },
      submitExit: async () => undefined,
      onOptionTick: () => undefined,
      onEvent: (fn) => {
        listener = fn;
        return () => undefined;
      },
      engageBrokerKillSwitch: async (reason) => {
        killSwitch.push(reason);
      },
      close: async () => undefined,
    };
    const harness = build({ BROKER_KILL_SWITCH_ON_BREACH: 'true' }, { execution });
    await harness.orchestrator.start();
    await triggerBreakout(harness);

    assert.equal(entries.length, 1);
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'HALTED');
    assert.match(harness.orchestrator.agent('NIFTY')?.haltedBecause ?? '', /entry unconfirmed/);
    assert.equal(killSwitch.length, 1);
    assert.match(killSwitch[0] ?? '', /NIFTY: entry unconfirmed/);
    assert.ok(harness.orchestrator.dayBook.snapshot().killSwitchReason);
  });

  it('should retry a failed broker kill switch after a backoff and alert once', async () => {
    const attempts: string[] = [];
    let listener: ((event: ExecutionEvent) => void) | undefined;
    const execution: ExecutionPort = {
      mode: 'live',
      protection: 'EXCHANGE_BRACKET',
      submitEntry: async (order) => {
        listener?.({ kind: 'ENTRY_UNCONFIRMED', correlationId: order.correlationId, underlying: 'NIFTY', reason: 'timeout' });
      },
      submitExit: async () => undefined,
      onOptionTick: () => undefined,
      onEvent: (fn) => {
        listener = fn;
        return () => undefined;
      },
      engageBrokerKillSwitch: async (reason) => {
        attempts.push(reason);
        if (attempts.length < 3) {
          throw new Error('kill switch status read back DEACTIVATE');
        }
      },
      close: async () => undefined,
    };
    const harness = build({ BROKER_KILL_SWITCH_ON_BREACH: 'true' }, { execution });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    await settle(harness.orchestrator);
    assert.equal(attempts.length, 1);

    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    assert.equal(attempts.length, 1, 'no retry inside the backoff');

    harness.setClock('09:46:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    harness.setClock('09:47:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    assert.equal(attempts.length, 3);

    harness.setClock('09:48:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    assert.equal(attempts.length, 3, 'stops once the switch is confirmed');
    assert.equal(types(harness).filter((type) => type === 'broker_kill_switch_failed').length, 1, 'alerted once per failure streak');
  });

  it('should still flatten a position filled late while halted, and engage the broker kill switch only after', async () => {
    const venue = scriptedVenue({ exit: 'FILL' });
    const harness = build({ BROKER_KILL_SWITCH_ON_BREACH: 'true' }, { execution: venue.port });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'HALTED');
    assert.equal(venue.killSwitch.length, 1, 'nothing is open yet, so it is tried at once');

    venue.lateFill(75, 101);
    await settle(harness.orchestrator);
    assert.equal(harness.orchestrator.agent('NIFTY')?.openPositions.length, 1);

    harness.setClock('15:05:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    assert.deepEqual(venue.exits.map((order) => order.reason), ['EOD_FLATTEN']);
    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'EOD_FLATTEN');
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'HALTED', 'the halt still needs an operator');

    clockTick(harness.orchestrator);
    assert.equal(venue.killSwitch.length, 2, 'tried again once the late position is closed');
    clockTick(harness.orchestrator);
    assert.equal(venue.killSwitch.length, 2, 'not repeated while nothing changes');
  });

  it('should accept an operator close for a position filled late while halted', async () => {
    const venue = scriptedVenue({ exit: 'FILL' });
    const harness = build({}, { execution: venue.port });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    venue.lateFill(75, 101);
    await settle(harness.orchestrator);

    assert.match(harness.orchestrator.requestManualExit('NIFTY'), /close requested/);
    await settle(harness.orchestrator);
    assert.deepEqual(venue.exits.map((order) => order.reason), ['MANUAL']);
    assert.equal(harness.orchestrator.agent('NIFTY')?.openPositions.length, 0);
  });

  it('should not resend an exit whose outcome is unknown while halted', async () => {
    const venue = scriptedVenue({ exit: 'UNCONFIRMED' });
    const harness = build({ BROKER_KILL_SWITCH_ON_BREACH: 'true' }, { execution: venue.port });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    venue.lateFill(75, 101);
    await settle(harness.orchestrator);

    harness.setClock('15:05:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    harness.setClock('15:06:00');
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
    assert.equal(venue.exits.length, 1, 'a second SELL could leave the account net short');
    assert.equal(venue.killSwitch.length, 1, 'only the attempt made at the halt; none while a position is open');
  });

  it('flattens every open position on shutdown and then reports flat', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    await harness.orchestrator.stop();
    const closed = harness.events.find((event) => event.type === 'trade_closed');
    assert.equal(closed?.payload['reason'], 'SHUTDOWN');
    assert.equal(harness.orchestrator.agent('NIFTY')?.isFlat(), true);
  });
});

describe('runtime: operator actions and cockpit snapshot', () => {
  it('reports the phase as RUNNING once started and FAILED with the reason when the start is refused', async () => {
    const running = build();
    await running.orchestrator.start();
    assert.equal(running.orchestrator.snapshot().phase, 'RUNNING');
    assert.equal(running.orchestrator.snapshot().underlyings[0]?.symbol, 'NIFTY');

    const refused = build({}, { brokerOpen: 1 });
    await assert.rejects(refused.orchestrator.start(), /open option position/);
    const failed = refused.orchestrator.snapshot();
    assert.equal(failed.phase, 'FAILED');
    assert.match(failed.phaseDetail ?? '', /open option position/);
  });

  it('closes the selected position through the normal exit path with reason MANUAL', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.position?.quantity, 75);

    assert.match(harness.orchestrator.requestManualExit('NIFTY'), /close requested/);
    await settle(harness.orchestrator);

    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'MANUAL');
    const view = harness.orchestrator.snapshot().underlyings[0];
    assert.equal(view?.position, undefined);
    assert.equal(view?.lastExit?.reason, 'MANUAL');
    assert.equal(view?.state, 'IDLE');
  });

  it('says why there is nothing to close instead of acting', async () => {
    const harness = build();
    await harness.orchestrator.start();
    assert.match(harness.orchestrator.requestManualExit('NIFTY'), /no open position/);
    assert.match(harness.orchestrator.requestManualExit('SENSEX'), /not traded by this agent/);
    assert.equal(harness.events.some((event) => event.type === 'exit_submitted'), false);
  });

  it('blocks new entries on request and clears the block only when nothing forbids it', async () => {
    const harness = build();
    await harness.orchestrator.start();
    assert.match(harness.orchestrator.toggleEntryBlock(), /new entries blocked/);
    assert.ok(harness.orchestrator.snapshot().day.killSwitchReason?.startsWith('operator entry block'));
    assert.match(harness.orchestrator.toggleEntryBlock(), /entry block cleared/);
    assert.equal(harness.orchestrator.snapshot().day.killSwitchReason, undefined);
  });

  it('refuses to clear the block while the day has breached its loss limit', async () => {
    const harness = build();
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    harness.setClock('10:05:00');
    optionTick(harness, '48001', 15);
    await settle(harness.orchestrator);
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);

    assert.ok(harness.orchestrator.snapshot().day.killSwitchReason?.startsWith('daily loss'));
    assert.match(harness.orchestrator.toggleEntryBlock(), /daily loss limit is breached/);
    assert.ok(harness.orchestrator.snapshot().day.killSwitchReason?.startsWith('daily loss'));
  });
});

/** Lets queued microtasks and immediates run, without waiting for the serial queue to drain. */
async function yieldToEventLoop(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
}

function gate(): { wait: Promise<void>; release: () => void } {
  let release!: () => void;
  const wait = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { wait, release };
}

describe('runtime: shutdown exits', () => {
  it('keeps retrying a rejected shutdown exit until it fills', async () => {
    const exits: ExitOrder[] = [];
    let listener: ((event: ExecutionEvent) => void) | undefined;
    let rejectNext = 1;
    let harness: Harness | undefined;
    const at = () => harness?.now() ?? 0;
    const execution: ExecutionPort = {
      mode: 'live',
      protection: 'EXCHANGE_BRACKET',
      submitEntry: async (order) => {
        listener?.({ kind: 'ENTRY_FILLED', correlationId: order.correlationId, underlying: 'NIFTY', quantity: order.quantity, averagePrice: order.entryReference, at: at() });
      },
      submitExit: async (order) => {
        exits.push(order);
        if (rejectNext > 0) {
          rejectNext -= 1;
          listener?.({ kind: 'EXIT_REJECTED', correlationId: order.correlationId, underlying: 'NIFTY', positionId: order.positionId, reason: 'venue rejected' });
          return;
        }
        listener?.({ kind: 'EXIT_FILLED', correlationId: order.correlationId, underlying: 'NIFTY', positionId: order.positionId, quantity: order.quantity, averagePrice: order.referencePrice, reason: order.reason, at: at() });
      },
      onOptionTick: () => undefined,
      onEvent: (fn) => {
        listener = fn;
        return () => undefined;
      },
      close: async () => undefined,
    };
    harness = build({}, { execution });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.ok(harness.orchestrator.agent('NIFTY')?.openPosition, 'a position is open before the stop');

    // The venue rejects the first SELL. The 10 s backoff runs on the injected clock, so move it past
    // the backoff while stop is polling. No option tick arrives during the stop.
    const stopping = harness.orchestrator.stop();
    setTimeout(() => harness?.setClock('10:05:00'), 100);
    await stopping;

    assert.deepEqual(exits.map((order) => order.reason), ['SHUTDOWN', 'SHUTDOWN']);
    assert.equal(types(harness).filter((type) => type === 'exit_rejected').length, 1);
    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'SHUTDOWN');
    assert.equal(harness.orchestrator.agent('NIFTY')?.isFlat(), true);
  });
});

describe('runtime: entries signalled before a stop, a block or a halt', () => {
  it('does not submit an entry that was signalled before a stop, and stop waits for the signal to settle', async () => {
    const expiries = gate();
    const harness = build({}, { expiriesGate: expiries.wait });
    await harness.orchestrator.start();
    harness.setClock('09:40:10');
    spotTick(harness, 101.5, '09:40:10');
    harness.setClock('09:45:05');
    spotTick(harness, 101.6, '09:45:05');
    await yieldToEventLoop();
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'SIGNAL_DETECTED');
    assert.equal(harness.orchestrator.agent('NIFTY')?.isFlat(), false, 'a signal in preparation is not flat');

    const stopping = harness.orchestrator.stop();
    expiries.release();
    await stopping;

    assert.equal(types(harness).includes('entry_submitted'), false);
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'ENTRY_BLOCKED');
    assert.equal(harness.orchestrator.agent('NIFTY')?.isFlat(), true);
    assert.equal(harness.orchestrator.snapshot().phase, 'STOPPED');
  });

  it('does not submit an entry when an operator block lands during the advisor review', async () => {
    const verdict = gate();
    const advisor: TradeAdvisor = {
      review: async () => {
        await verdict.wait;
        return { decision: 'ENTER', confidence: 0.9, reason: 'trend holds', source: 'llm' } as AdvisoryVerdict;
      },
    };
    const harness = build({}, { advisor });
    await harness.orchestrator.start();
    harness.setClock('09:40:10');
    spotTick(harness, 101.5, '09:40:10');
    harness.setClock('09:45:05');
    spotTick(harness, 101.6, '09:45:05');
    await yieldToEventLoop();
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'SIGNAL_DETECTED');

    assert.match(harness.orchestrator.toggleEntryBlock(), /new entries blocked/);
    verdict.release();
    await settle(harness.orchestrator);

    assert.equal(types(harness).includes('entry_submitted'), false);
    const dropped = harness.events.find((event) => event.type === 'signal_dropped');
    assert.equal(dropped?.payload['code'], 'ENTRY_BLOCKED');
    assert.match(String(dropped?.payload['detail'] ?? ''), /operator entry block/);
  });
});

describe('runtime: daily-loss breach under an operator block', () => {
  it('still records the breach and arms the broker kill switch once flat, even when an operator block holds the switch', async () => {
    const killSwitch: string[] = [];
    const harness = build({ BROKER_KILL_SWITCH_ON_BREACH: 'true' }, { killSwitch });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.match(harness.orchestrator.toggleEntryBlock(), /new entries blocked/);

    harness.setClock('10:05:00');
    optionTick(harness, '48001', 15);
    await settle(harness.orchestrator);
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);

    assert.equal(types(harness).filter((type) => type === 'daily_loss_breach').length, 1);
    // The paper bracket stop fills first at 15, so the close reason is STOP_LOSS. The breach is still recorded.
    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'STOP_LOSS');
    assert.equal(killSwitch.length, 1, 'the broker kill switch is engaged exactly once');
    assert.match(killSwitch[0] ?? '', /daily loss/);
    assert.match(harness.orchestrator.snapshot().day.killSwitchReason ?? '', /operator entry block/, 'the operator reason is kept');
    assert.match(harness.orchestrator.dayBook.snapshot().dailyLossBreach ?? '', /daily loss/, 'the breach stays latched');
  });
});

describe('runtime: stop during start', () => {
  it('a stop during the feed start leaves no subscriptions or clock running, and ends STOPPED', async () => {
    const feedStart = gate();
    const harness = build({}, { feedGate: feedStart.wait });
    const starting = harness.orchestrator.start();
    for (let i = 0; i < 100 && !harness.feed.startCalled; i += 1) {
      await yieldToEventLoop();
    }
    assert.equal(harness.feed.startCalled, true, 'start reached the feed');
    assert.equal(harness.orchestrator.snapshot().phase, 'STARTING');

    const stopping = harness.orchestrator.stop();
    feedStart.release();
    await Promise.all([starting, stopping]);

    assert.equal(harness.feed.subscribed.size, 0, 'nothing is subscribed after the stop');
    assert.equal(harness.orchestrator.snapshot().phase, 'STOPPED');
  });

  it('does not let a feed connect that never completes hang the stop', async () => {
    const feedStart = gate();
    const harness = build({}, { feedGate: feedStart.wait });
    const starting = harness.orchestrator.start();
    for (let i = 0; i < 100 && !harness.feed.startCalled; i += 1) {
      await yieldToEventLoop();
    }

    // The feed never finishes connecting. Stop must return within its shutdown timeout anyway.
    await harness.orchestrator.stop();
    assert.equal(harness.orchestrator.snapshot().phase, 'STOPPED');

    // When the connect finally completes, nothing is subscribed and the start resolves quietly.
    feedStart.release();
    await starting;
    assert.equal(harness.feed.subscribed.size, 0);
  });
});

describe('runtime: durable intents and the trading gate', () => {
  /** Ticks to the 09:45 breakout without settling, so a test can act while the entry is still being prepared. */
  async function breakoutWithoutSettling(harness: Harness): Promise<void> {
    harness.setClock('09:40:10');
    spotTick(harness, 101.5, '09:40:10');
    harness.setClock('09:45:05');
    spotTick(harness, 101.6, '09:45:05');
    for (let i = 0; i < 20; i += 1) {
      await yieldToEventLoop();
    }
  }

  it('sends no entry when its intent is not durable, and reports why', async () => {
    const harness = build({}, { durable: async (type) => {
      if (type === 'entry_submitted') {
        throw new Error('ledger unavailable');
      }
    } });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.position, undefined);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.lastDrop?.code, 'INTENT_NOT_DURABLE');
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'IDLE');
  });

  it('drops an entry whose intent is still being written when a block lands, and records it as rejected, not sent', async () => {
    const release = gate();
    const harness = build({}, { durable: async (type) => {
      if (type === 'entry_submitted') {
        await release.wait;
      }
    } });
    await harness.orchestrator.start();
    await breakoutWithoutSettling(harness);
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'SIGNAL_DETECTED', 'the intent is being written');

    assert.match(harness.orchestrator.toggleEntryBlock(), /new entries blocked/);
    release.release();
    await settle(harness.orchestrator);

    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.position, undefined, 'the order was not sent');
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.lastDrop?.code, 'ENTRY_BLOCKED');
    const rejected = harness.events.find((event) => event.type === 'entry_rejected');
    assert.match(String(rejected?.payload['reason'] ?? ''), /^ABORTED_AFTER_INTENT: operator entry block/);
  });

  it('gives up on an intent that is not durable within the deadline, so a stalled database cannot hold the queue', async () => {
    const harness = build({}, { durable: async (type) => {
      if (type === 'entry_submitted') {
        await new Promise<void>(() => undefined);
      }
    } });
    await harness.orchestrator.start();
    harness.setClock('09:40:10');
    spotTick(harness, 101.5, '09:40:10');
    harness.setClock('09:45:05');
    spotTick(harness, 101.6, '09:45:05');
    const started = Date.now();
    await settle(harness.orchestrator);
    assert.ok(Date.now() - started >= 1_900, 'the wait ends at the deadline, not earlier');
    const dropped = harness.orchestrator.snapshot().underlyings[0]?.lastDrop;
    assert.equal(dropped?.code, 'INTENT_NOT_DURABLE');
    assert.match(dropped?.detail ?? '', /not durable within 2000 ms/);
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.position, undefined);
  });

  it('still sends an exit when its intent is not durable, and records the gap', async () => {
    const harness = build({}, { durable: async (type) => {
      if (type === 'exit_submitted') {
        throw new Error('ledger unavailable');
      }
    } });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.match(harness.orchestrator.requestManualExit('NIFTY'), /close requested/);
    await settle(harness.orchestrator);
    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'MANUAL', 'the exit went out');
    assert.ok(harness.events.some((event) => event.type === 'audit_gap'), 'the missing intent is recorded as an audit gap');
  });

  it('honours a gate exit block when one is reported, and keeps the position open', async () => {
    let exitBlock: string | undefined;
    const tradingGate: TradingGate = { entryBlock: () => undefined, exitBlock: () => exitBlock };
    const harness = build({}, { gate: tradingGate });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    exitBlock = 'broker exit path is fail-stopped';
    requestManual(harness);
    await settle(harness.orchestrator);
    assert.equal(harness.events.some((event) => event.type === 'exit_submitted'), false, 'no SELL is sent');
    assert.equal(harness.orchestrator.snapshot().underlyings[0]?.position?.quantity, 75, 'the position is still open');
    assert.equal(harness.orchestrator.agent('NIFTY')?.state, 'RISK_MANAGEMENT_ACTIVE');
  });

  it('sends the exit after the trading lease is lost: a protective exit must not wait on the lease', async () => {
    const leaseHolds = { value: true };
    const gate = ledgerAndLeaseGate({ unconfirmedEvents: () => 0, leaseHolds: () => leaseHolds.value });
    const harness = build({}, { gate });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    leaseHolds.value = false;
    requestManual(harness);
    await settle(harness.orchestrator);
    assert.equal(harness.events.some((event) => event.type === 'exit_submitted'), true, 'the SELL goes out');
    assert.equal(harness.events.find((event) => event.type === 'trade_closed')?.payload['reason'], 'MANUAL');
    assert.equal(gate.entryBlock(), 'trading lease lost; another run may be trading this account', 'entries stay blocked');
  });

  it('holds new entries while events are not yet confirmed, and sends none', async () => {
    const tradingGate: TradingGate = {
      entryBlock: () => '2 event(s) are not yet confirmed in the journal and ledger; entries wait',
      exitBlock: () => undefined,
    };
    const harness = build({}, { gate: tradingGate });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.equal(harness.events.some((event) => event.type === 'entry_submitted'), false);
    assert.match(harness.orchestrator.snapshot().underlyings[0]?.lastDrop?.detail ?? '', /not yet confirmed/);
  });

  it('refuses to start while the broker reports live orders, even with no position yet', async () => {
    const harness = build({}, { brokerLiveOrders: 1 });
    await assert.rejects(harness.orchestrator.start(), /not in a terminal status/);
    assert.equal(harness.orchestrator.snapshot().phase, 'FAILED');
  });

  it('writes halts and kill-switch activations durably', async () => {
    const durableTypes: string[] = [];
    const execution: ExecutionPort = {
      mode: 'live',
      protection: 'EXCHANGE_BRACKET',
      submitEntry: async (order) => {
        listener?.({ kind: 'ENTRY_UNCONFIRMED', correlationId: order.correlationId, underlying: 'NIFTY', reason: 'timeout' });
      },
      submitExit: async () => undefined,
      onOptionTick: () => undefined,
      onEvent: (fn) => {
        listener = fn;
        return () => undefined;
      },
      close: async () => undefined,
    };
    let listener: ((event: ExecutionEvent) => void) | undefined;
    const harness = build({}, { execution, durable: async (type) => {
      durableTypes.push(type);
    } });
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    assert.ok(durableTypes.includes('halted'), 'the halt is durable');
    assert.ok(durableTypes.includes('book_kill_switch'), 'the kill switch it set is durable');
  });

  it('triggers a test trade directly on demand and executes the trade lifecycle', async () => {
    const harness = build();
    await harness.orchestrator.start();
    harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp: 101.2, ltt: harness.now() });
    const msg = harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    assert.match(msg, /test BULLISH signal triggered/);
    await settle(harness.orchestrator);
    assert.ok(harness.events.some((event) => event.type === 'entry_submitted'), 'test trade triggered entry');
  });

  it('triggers test trade on the current trend side when direction is omitted', async () => {
    const harness = build();
    await harness.orchestrator.start();
    harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp: 101.2, ltt: harness.now() });
    // In this harness, warmup had an uptrend, so currentTrendDirection() is BULLISH
    const msg = harness.orchestrator.triggerTestTrade('NIFTY');
    assert.match(msg, /test BULLISH signal triggered/);
  });

  it('can open both CE and PE positions concurrently on the same underlying', async () => {
    const harness = build({
      MAX_OPEN_POSITIONS: '6',
      MAX_POSITIONS_PER_UNDERLYING: '2',
      MAX_POSITIONS_PER_SIDE: '1',
      // Two trades risk 2 × 2272.5; the day must be able to absorb both stops.
      MAX_DAILY_LOSS_PCT: '2',
    });
    await harness.orchestrator.start();
    harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp: 101.2, ltt: harness.now() });

    const msg1 = harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    assert.match(msg1, /test BULLISH signal triggered/);
    await settle(harness.orchestrator);

    const msg2 = harness.orchestrator.triggerTestTrade('NIFTY', 'BEARISH');
    assert.match(msg2, /test BEARISH signal triggered/);
    await settle(harness.orchestrator);

    const snapshot = harness.orchestrator.snapshot();
    const nifty = snapshot.underlyings[0];
    assert.ok(nifty !== undefined);
    assert.equal(nifty.positions.length, 2);
    assert.equal(snapshot.day.openPositions, 2);
    const expectedAllocated = nifty.positions.reduce((acc, p) => acc + p.averagePrice * p.quantity, 0);
    assert.equal(snapshot.allocatedBalanceInr, expectedAllocated);
    assert.equal(snapshot.availableBalanceInr, snapshot.currentBalanceInr - snapshot.allocatedBalanceInr);
    assert.equal(snapshot.realTimeBalanceInr, snapshot.currentBalanceInr + snapshot.day.unrealizedPnlInr);
    assert.equal(snapshot.initialCapitalInr, 300_000);

    const msg3 = harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    assert.match(msg3, /cannot test trade while CE state is RISK_MANAGEMENT_ACTIVE/);
  });

  it('should refuse a second position whose stop, with the first, could breach the daily limit', async () => {
    const harness = build({ MAX_OPEN_POSITIONS: '6', MAX_POSITIONS_PER_UNDERLYING: '2' });
    await harness.orchestrator.start();
    harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp: 101.2, ltt: harness.now() });
    harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    await settle(harness.orchestrator);
    harness.orchestrator.triggerTestTrade('NIFTY', 'BEARISH');
    await settle(harness.orchestrator);

    assert.equal(harness.orchestrator.snapshot().day.openPositions, 1);
    assert.equal(harness.events.find((event) => event.type === 'signal_dropped')?.payload['code'], 'DAILY_LOSS_AT_RISK');
  });

  it('should journal an operator test trade as strategy test, apart from real signals', async () => {
    const harness = build();
    await harness.orchestrator.start();
    harness.feed.emit({ exchangeSegment: 'IDX_I', securityId: '13', ltp: 101.2, ltt: harness.now() });
    harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    await settle(harness.orchestrator);
    assert.equal(harness.events.find((event) => event.type === 'entry_submitted')?.payload['strategy'], 'test');
  });

  it('should journal posture and strategy changes', async () => {
    const harness = build();
    harness.orchestrator.cyclePosture();
    harness.orchestrator.toggleStrategy('trend');
    const changes = harness.events.filter((event) => event.type.startsWith('strategy_'));
    assert.deepEqual(
      changes.map((event) => [event.type, event.payload]),
      [
        ['strategy_posture', { posture: 'confirmed' }],
        ['strategy_toggled', { id: 'trend', enabled: false }],
      ],
    );
  });

  it('rejects test trades in live mode', async () => {
    const harness = build({ MODE: 'live', LIVE_TRADING_ACK: 'I_ACCEPT_LIVE_ORDER_RISK', REDIS_URL: 'redis://test.invalid' });
    const msg = harness.orchestrator.triggerTestTrade('NIFTY', 'BULLISH');
    assert.match(msg, /disabled in live mode/);
  });
});

/** Requests a manual close of the selected underlying, as the operator's key does. */
function requestManual(harness: Harness): void {
  harness.orchestrator.requestManualExit('NIFTY');
}

describe('stale option ticks on an open client-side position', () => {
  /** A breakout fills the CE at 09:45:05, and the first option tick arrives with the fill. */
  async function openPosition(harness: Harness): Promise<void> {
    await harness.orchestrator.start();
    await triggerBreakout(harness);
    optionTick(harness, CE.securityId, 102);
  }

  /** Moves the clock and runs the clock path, which is where the watchdog decides. */
  async function atClock(harness: Harness, at: string): Promise<void> {
    harness.setClock(at);
    clockTick(harness.orchestrator);
    await settle(harness.orchestrator);
  }

  const entryBlock = (harness: Harness): string | undefined =>
    (harness.orchestrator.agent('NIFTY') as unknown as { entryBlockReason(): string | undefined }).entryBlockReason();

  it('records position_stale once option ticks stop for longer than FEED_STALE_MS', async () => {
    const harness = build();
    await openPosition(harness);
    await atClock(harness, '09:45:20');
    assert.equal(harness.events.filter((event) => event.type === 'position_stale').length, 1);
    await atClock(harness, '09:45:21');
    assert.equal(harness.events.filter((event) => event.type === 'position_stale').length, 1, 'one record per stale episode');
  });

  it('exits a client-side position with STALE_DATA once the silence reaches the grace period, and only once', async () => {
    const harness = build();
    await openPosition(harness);
    await atClock(harness, '09:45:20');
    assert.equal(harness.events.filter((event) => event.type === 'exit_submitted').length, 0, 'inside the grace period nothing is sold');
    await atClock(harness, '09:46:10');
    const exits = harness.events.filter((event) => event.type === 'exit_submitted');
    assert.equal(exits.length, 1);
    assert.equal(exits[0]?.payload['reason'], 'STALE_DATA');
    await atClock(harness, '09:46:12');
    assert.equal(harness.events.filter((event) => event.type === 'exit_submitted').length, 1, 'one exit per position');
  });

  it('blocks new entries on the underlying while its client-side position is stale', async () => {
    const harness = build();
    await openPosition(harness);
    await atClock(harness, '09:45:20');
    assert.match(entryBlock(harness) ?? '', /client-side protection stale/);
  });

  it('clears the stale state on the next option tick, and does not exit', async () => {
    const harness = build();
    await openPosition(harness);
    await atClock(harness, '09:45:20');
    optionTick(harness, CE.securityId, 103);
    await atClock(harness, '09:45:21');
    assert.equal(entryBlock(harness), undefined);
    assert.equal(harness.events.filter((event) => event.type === 'exit_submitted').length, 0);
  });

  it('leaves an exchange-held position alone: its stop is at the broker, not in the agent', async () => {
    const harness = build({}, { exchangeHeld: true });
    await openPosition(harness);
    await atClock(harness, '09:46:10');
    assert.equal(harness.events.some((event) => event.type === 'position_stale'), false);
    assert.equal(harness.events.filter((event) => event.type === 'exit_submitted').length, 0);
  });
});

describe('broker P&L exit arming at start', () => {
  const LIVE_ENV = {
    MODE: 'live',
    LIVE_TRADING_ACK: 'I_ACCEPT_LIVE_ORDER_RISK',
    REDIS_URL: 'redis://cache.test.invalid:6379/0',
    BROKER_PNL_EXIT: 'on',
  };

  it('arms the broker P&L exit at the daily loss limit in live mode', async () => {
    const armed: number[] = [];
    const harness = build(LIVE_ENV, { brokerPnlExitArm: armed });
    await harness.orchestrator.start();
    assert.deepEqual(armed, [3_000], 'CAPITAL_INR 300000 at 1% a day');
  });

  it('does not arm the broker P&L exit on paper, even when the setting is on', async () => {
    const armed: number[] = [];
    const harness = build({ BROKER_PNL_EXIT: 'on' }, { brokerPnlExitArm: armed });
    await harness.orchestrator.start();
    assert.deepEqual(armed, []);
  });
});

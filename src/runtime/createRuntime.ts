import { OllamaClient } from '@nemesis-oss/ollama-sdk';
import { createDhanClient } from '../dhan/client.js';
import type { DhanClient } from '@nemesis-oss/dhanhq-sdk';
import { DhanSandboxGateway } from '../dhan/sandboxGateway.js';
import { GatewayExecutionPort } from '../execution/gatewayPort.js';
import type { OrderGateway } from '../execution/orderGateway.js';
import { PaperExchangeClient } from '../paper/exchangeClient.js';
import { PaperExchangeGateway } from '../paper/exchangeGateway.js';
import { DhanFeed } from '../dhan/feed.js';
import { InstrumentMaster } from '../dhan/instrumentMaster.js';
import { DhanMarketData } from '../dhan/marketData.js';
import { LiveExecutionPort, TERMINAL_ORDER_STATUSES, type LiveClient } from '../dhan/liveExecution.js';
import type { AgentConfig } from '../config.js';
import type { ExecutionPort } from '../execution/ports.js';
import { PostgresPaperExecutionPort } from '../execution/postgresPaper.js';
import { PostgresPaperStore, toPaise } from '../execution/paperStore.js';
import { OllamaTradeAdvisor, type TradeAdvisor } from '../llm/advisor.js';
import type { UnderlyingSpec } from '../domain/types.js';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { EventLog, journalFileName } from '../ops/eventLog.js';
import { buildAlertListener } from '../ops/alerts.js';
import { ChainRecorder } from '../ops/chainRecorder.js';
import { restoreDayBook } from '../ops/dayState.js';
import { adverseCostsFor } from '../risk/allInLoss.js';
import { DayBook } from '../risk/dayBook.js';
import { createConsoleLogger, RingLogger, type Logger } from '../ops/logger.js';
import { backfillDay } from '../persistence/backfill.js';
import type { PostgresLedger } from '../persistence/ledger.js';
import { errorMessage } from '../persistence/redact.js';
import { scopeJournalLines } from '../persistence/scope.js';
import { openSession, type PersistenceSession } from '../persistence/session.js';
import { istParts, shiftDateKey } from '../time/ist.js';
import type { MarketPort } from './ports.js';
import { Orchestrator } from './orchestrator.js';
import { createSharedChainContextReader } from '../options/sharedChainContext.js';
import { ledgerAndLeaseGate } from './tradingGate.js';

export interface Runtime {
  readonly orchestrator: Orchestrator;
  readonly logger: Logger;
  /** Set in cockpit mode: the bounded log the terminal screen renders. */
  readonly records: RingLogger | undefined;
}

/**
 * Composes the object graph from validated config. Every mode shares the same market-data path (instruments,
 * charts, option chain, feed) on the live Dhan credentials. Only the order venue differs:
 *   live    -> Dhan production account
 *   sandbox -> Dhan sandbox account (sandbox credentials and base URL)
 *   paper   -> PostgreSQL paper venue (wallet, orders, positions, P&L)
 * Index specs are resolved from the scrip master up front, so an unknown index fails at startup rather than on
 * the first signal.
 *
 * Storage: the journal file is always written, and every line carries its mode and client. When DATABASE_URL
 * is set, the ledger is the source for restoring the day, after the journal is backfilled into it. The
 * trading lease lives in PostgreSQL. Redis holds the account rate gate and the contract cache. Any failure
 * here closes what was opened and refuses to start.
 */
export async function buildRuntime(
  config: AgentConfig,
  now: () => number = Date.now,
  options: { cockpit?: boolean } = {},
): Promise<Runtime> {
  const records = options.cockpit === true ? new RingLogger(200, now) : undefined;
  const logger: Logger = records ?? createConsoleLogger(undefined, now);
  const session = await openSession(config, { logger, now });
  try {
    return await compose(config, now, logger, records, session);
  } catch (error) {
    await session.close('startup failed');
    throw error;
  }
}

async function compose(
  config: AgentConfig,
  now: () => number,
  logger: Logger,
  records: RingLogger | undefined,
  session: PersistenceSession,
): Promise<Runtime> {
  const mode = config.mode;
  const clientId = config.dhan.clientId;
  const scope = { mode, clientId };
  const alertListener = buildAlertListener(config.ops, logger);
  const events = new EventLog({
    directory: config.ops.eventLogDir,
    runId: session.runId,
    scope,
    ...(session.ledger === undefined ? {} : { ledger: session.ledger }),
    onError: (error) => logger.error('event log write failed', { error: errorMessage(error, session.secrets) }),
    ...(alertListener === undefined ? {} : { onEvent: alertListener }),
    now,
  });

  // Market data is always the live Dhan feed. In sandbox mode the same client sends orders to the sandbox (SDK hybrid mode).
  const dataClient = await createDhanClient(config.dhan, { logger, now, ...(config.sandbox === undefined ? {} : { sandbox: config.sandbox }) });
  const master = new InstrumentMaster(dataClient.instruments, () => istParts(now()).date, { cache: session.cache, now });
  const marketData = new DhanMarketData(dataClient, {
    istShiftedTimestamps: config.feed.istShiftedTimestamps,
    now,
    rateGate: session.rateGate,
    accountKey: clientId,
  });
  const feed = new DhanFeed(dataClient, {
    istShiftedTimestamps: config.feed.feedIstShifted,
    marketFeedMode: config.feed.marketFeedMode,
    now,
    logger,
    connectOrderUpdates: config.mode === 'live',
    onTerminalDisconnect: (code) => {
      events.record('feed_terminal', { code });
    },
  });

  const paperExchange = config.mode === 'paper' && config.paper.backend === 'exchange' ? buildPaperExchangeClient(config) : undefined;
  if (paperExchange !== undefined) {
    await assertInrAccount(paperExchange);
  }
  const venue = config.mode === 'paper' && config.paper.backend === 'postgres' ? await openPaperVenue(config, session, logger, now) : undefined;
  const gateway = buildGateway(config, dataClient, paperExchange, logger, now);

  const market: MarketPort = {
    intradayCandles: (spot, barMinutes, fromDate, toDate) => marketData.intradayCandles(spot, barMinutes, fromDate, toDate),
    listExpiries: (spot) => marketData.listExpiries(spot),
    optionChain: (spot, expiry) => marketData.optionChain(spot, expiry),
    optionContracts: (underlying, optionSegment) => master.optionContracts(underlying, optionSegment),
    availableFunds: () => {
      if (venue !== undefined) {
        return venue.cash();
      }
      if (paperExchange !== undefined) {
        return paperExchange.availableBalance();
      }
      // Live and sandbox: the trading funds call. In sandbox mode the SDK routes it to the sandbox account.
      return marketData.availableFunds();
    },
    // The venue's own open positions play the role of the broker book. Paper_exchange and sandbox answer from their server.
    brokerOpenOptionCount: async () => {
      if (venue !== undefined) {
        return venue.openPositionCount();
      }
      if (gateway !== undefined && config.mode !== 'live') {
        return gateway.openPositionCount();
      }
      return countOpenOptionLegs(dataClient);
    },
    brokerOpenPositions: async () => {
      if (venue !== undefined) {
        return venue.getOpenPositions();
      }
      return [];
    },
    brokerLiveOrderCount: async () => {
      if (config.mode === 'live') {
        return countLiveOrders(dataClient);
      }
      if (config.mode === 'sandbox') {
        return countLiveRegularOrders(dataClient);
      }
      return 0;
    },
  };

  let execution: ExecutionPort;
  if (config.mode === 'live') {
    execution = new LiveExecutionPort(dataClient as LiveClient, {
      mode: 'live',
      orderTimeoutMs: config.ops.orderTimeoutMs,
      reconcileIntervalMs: config.ops.reconcileIntervalMs,
      logger,
      now,
    });
  } else if (config.mode === 'sandbox' && gateway !== undefined) {
    execution = new GatewayExecutionPort(gateway, { mode: 'sandbox', logger, now });
  } else if (paperExchange !== undefined && gateway !== undefined) {
    execution = new GatewayExecutionPort(gateway, { mode: 'paper', logger, now });
  } else if (venue !== undefined) {
    execution = venue;
  } else {
    throw new Error(`no order venue for ${config.mode} mode`);
  }

  const advisor = buildAdvisor(config, logger);

  const specs: UnderlyingSpec[] = [];
  for (const underlying of config.underlyings) {
    const spot = await master.resolveSpot(underlying.symbol);
    specs.push({ symbol: underlying.symbol, spot, optionSegment: underlying.optionSegment });
  }
  if (venue !== undefined) {
    await settleExpiredPositions(venue, specs, market, config.strategy.barMinutes, logger);
  }

  const dayBook = new DayBook(now(), config.exits.cooldownSeconds * 1000, config.capital.enforceDailyLoss);
  const dayKey = istParts(now()).date;
  const lines =
    session.ledger === undefined
      ? await readJournal(config.ops.eventLogDir, dayKey, scope)
      : await restoreFromLedger(session.ledger, config.ops.eventLogDir, dayKey, scope, logger, session.secrets);
  // The restart booking follows the enforced policy. Otherwise it books planned stop distance plus charges, as it did before OTA-311.
  const restartCosts = config.capital.allInRiskPolicy === 'enforce' ? adverseCostsFor(config) : { halfSpreadPct: 0, stopSlippagePct: 0 };
  const restored = restoreDayBook(dayBook, lines, dayKey, restartCosts);
  logger.info('day state restored', {
    source: session.ledger === undefined ? 'journal' : 'ledger',
    eventsApplied: restored.eventsApplied,
    releasedUnresolved: restored.releasedUnresolved,
  });

  const openingCapitalInr = await openingCapital(config, venue, market, dayBook);

  const gate = ledgerAndLeaseGate({
    unconfirmedEvents: () => events.unconfirmedEvents(),
    leaseHolds: () => session.lease === undefined || session.lease.holds(),
  });

  // Shared chain truth (contract chain-context/1): when the session's Redis
  // is the unified one Rails publishes to, each agent's OI-resistance gate
  // reads Rails' analytics. No Redis (paper without REDIS_URL), or a
  // missing/stale key, falls back to local computation everywhere.
  const sharedChainContextFor = session.redis === undefined
    ? undefined
    : (underlying: string) => createSharedChainContextReader({ redis: session.redis!, underlying });

  const orchestrator = new Orchestrator(config, specs, {
    dayBook,
    openingCapitalInr,
    market,
    feed,
    execution,
    advisor,
    events,
    logger,
    now,
    gate,
    ...(sharedChainContextFor === undefined ? {} : { sharedChainContextFor }),
    closeSession: (reason) => session.close(reason, events.unconfirmedEvents()),
  });
  startChainRecorder(config, specs, market, logger, now);
  return { orchestrator, logger, records };
}

const CHAIN_RECORD_CHECK_MS = 30_000;

/** Read-only and unref'd: it never holds the process open, and a fetch in flight at exit is harmless. */
function startChainRecorder(config: AgentConfig, specs: readonly UnderlyingSpec[], market: MarketPort, logger: Logger, now: () => number): void {
  const recorder = new ChainRecorder({
    market,
    specs,
    directory: 'data/research/chains',
    barMinutes: config.strategy.barMinutes,
    minDaysToExpiry: config.contract.minDaysToExpiry,
    maxDaysToExpiry: config.contract.maxDaysToExpiry,
    logger,
  });
  let inFlight = false;
  setInterval(() => {
    if (inFlight) {
      return;
    }
    inFlight = true;
    void recorder.recordIfDue(now()).finally(() => {
      inFlight = false;
    });
  }, CHAIN_RECORD_CHECK_MS).unref();
}

/**
 * Backfills today's journal into the ledger, then returns the ledger's view of the day. A failed or
 * incomplete backfill throws, so the agent does not restore from a ledger that is missing events.
 */
async function restoreFromLedger(
  ledger: PostgresLedger,
  directory: string,
  dayKey: string,
  scope: { readonly mode: string; readonly clientId: string },
  logger: Logger,
  secrets: readonly string[],
): Promise<string[]> {
  try {
    const report = await backfillDay({ directory, tradingDay: dayKey, ledger });
    logger.info('journal backfilled into the ledger', { day: dayKey, lines: report.lines, inserted: report.inserted });
    const untagged = await ledger.untaggedDayCount(dayKey);
    if (untagged > 0) {
      throw new Error(`${untagged} ledger row(s) for ${dayKey} predate mode and client tags and cannot be attributed; move them aside before restoring`);
    }
    return await ledger.dayLines(dayKey, scope);
  } catch (error) {
    throw new Error(`cannot restore ${dayKey} from the ledger: ${errorMessage(error, secrets)}`);
  }
}

/** The paper_exchange client, built from validated config. The API key is never logged. */
function buildPaperExchangeClient(config: AgentConfig): PaperExchangeClient {
  const exchange = config.paper.exchange;
  if (exchange === undefined) {
    throw new Error('PAPER_BACKEND=exchange without a paper_exchange configuration');
  }
  return new PaperExchangeClient({ baseUrl: exchange.url, apiKey: exchange.apiKey, accountId: exchange.accountId, timeoutMs: 5_000 });
}

/**
 * Refuses to start against a paper_exchange account that is not INR. Indian option premiums are rupee amounts, so the
 * server would reject every order with CURRENCY_MISMATCH and the agent would halt on its first signal.
 */
async function assertInrAccount(client: PaperExchangeClient): Promise<void> {
  const { currency } = await client.account();
  if (currency !== 'INR') {
    throw new Error(
      `paper_exchange account is ${currency || 'of unknown currency'}; Indian options need an INR account. ` +
        'Create the account with currency INR on the paper_exchange server, or choose another account with PAPER_EXCHANGE_ACCOUNT_ID',
    );
  }
}

/**
 * The order gateway for the venue that takes orders in this mode, or undefined when the mode has none of its own (live
 * uses the super-order port, and the PostgreSQL paper venue is its own port).
 */
function buildGateway(
  config: AgentConfig,
  dataClient: DhanClient,
  paperExchange: PaperExchangeClient | undefined,
  logger: Logger,
  now: () => number,
): OrderGateway | undefined {
  if (config.mode === 'sandbox') {
    return new DhanSandboxGateway(dataClient, { orderTimeoutMs: config.ops.orderTimeoutMs, pollIntervalMs: 500, logger, now });
  }
  if (paperExchange !== undefined) {
    return new PaperExchangeGateway(paperExchange, { logger });
  }
  return undefined;
}

/**
 * Opens the PostgreSQL paper venue: creates the wallet on first use and loads the open positions. The venue needs
 * the database and the lease fence, both of which exist in paper mode because the config requires DATABASE_URL.
 */
/** Settles paper positions whose option expired while held, so a carried position cannot outlive its contract. */
async function settleExpiredPositions(
  venue: PostgresPaperExecutionPort,
  specs: readonly UnderlyingSpec[],
  market: MarketPort,
  barMinutes: number,
  logger: Logger,
): Promise<void> {
  const settled = await venue.settleExpired(async (underlying, expiry) => {
    const spec = specs.find((candidate) => candidate.symbol === underlying);
    if (spec === undefined) {
      throw new Error(`cannot settle an expired ${underlying} position: ${underlying} is not a configured underlying`);
    }
    const bars = await market.intradayCandles(spec.spot, barMinutes, expiry, shiftDateKey(expiry, 1));
    const close = bars.filter((bar) => istParts(bar.time).date === expiry).at(-1)?.close;
    if (close === undefined) {
      throw new Error(`cannot settle an expired ${underlying} position: no ${underlying} bars on expiry day ${expiry}`);
    }
    return close;
  });
  for (const position of settled) {
    logger.warn('expired paper position cash-settled at intrinsic value', { ...position });
  }
}

/**
 * Capital the day starts with. The paper wallet carries every earlier close and withdrawal, so it compounds; it
 * already holds today's restored closes, which come off so the day book does not count them twice. Other venues
 * keep no history here, so CAPITAL_INR stands in, capped by the broker cash so a smaller account sizes smaller.
 */
async function openingCapital(
  config: AgentConfig,
  venue: PostgresPaperExecutionPort | undefined,
  market: MarketPort,
  dayBook: DayBook,
): Promise<number> {
  if (venue === undefined) {
    return Math.min(config.capital.inr, await market.availableFunds());
  }
  const openPremiumInr = venue.getOpenPositions().reduce((sum, position) => sum + position.averagePrice * position.quantity, 0);
  return toPaise((await venue.cash()) + openPremiumInr - dayBook.snapshot().realizedPnlInr);
}

async function openPaperVenue(
  config: AgentConfig,
  session: PersistenceSession,
  logger: Logger,
  now: () => number,
): Promise<PostgresPaperExecutionPort> {
  if (session.pool === undefined || session.fence === undefined) {
    throw new Error('paper mode needs the PostgreSQL paper venue, and DATABASE_URL is not open');
  }
  const venue = new PostgresPaperExecutionPort(new PostgresPaperStore(session.pool, session.fence), {
    clientId: config.dhan.clientId,
    slippageBps: config.paper.slippageBps,
    initialCapitalInr: config.capital.inr,
    logger,
    now,
  });
  await venue.open();
  return venue;
}

function buildAdvisor(config: AgentConfig, logger: Logger): TradeAdvisor | undefined {
  if (!config.llm.enabled) {
    return undefined;
  }
  if (config.llm.model === undefined) {
    throw new Error('LLM_ADVISOR=on requires OLLAMA_MODEL');
  }
  const client = new OllamaClient({
    baseUrl: config.llm.host,
    ...(config.llm.apiKey === undefined ? {} : { apiKey: config.llm.apiKey }),
  });
  logger.info('llm advisor enabled', { host: config.llm.host, model: config.llm.model });
  return new OllamaTradeAdvisor(client, config.llm.model, config.llm.timeoutMs);
}

/**
 * Lines of today's journal file written by this mode and client. A missing file means no trading has been
 * journalled today, so there is nothing to restore. Lines from another mode or client are skipped. Untagged
 * lines predate tagging and cannot be attributed, so their presence refuses the restore.
 */
async function readJournal(directory: string, dayKey: string, scope: { readonly mode: string; readonly clientId: string }): Promise<string[]> {
  let text: string;
  try {
    text = await readFile(join(directory, journalFileName(dayKey)), 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      return [];
    }
    throw error;
  }
  return scopeJournalLines(text, scope, dayKey);
}

async function countLiveOrders(client: Pick<LiveClient, 'orders' | 'superOrders'>): Promise<number> {
  const [orders, superOrders] = await Promise.all([client.orders.list(), client.superOrders.list()]);
  const live = (status: string | undefined): boolean => status === undefined || !TERMINAL_ORDER_STATUSES.has(status);
  return orders.filter((order) => live(order.orderStatus)).length + superOrders.filter((order) => live(order.orderStatus)).length;
}

/** The sandbox serves no super orders (it answers 404), so only regular orders are counted there. */
async function countLiveRegularOrders(client: Pick<DhanClient, 'orders'>): Promise<number> {
  const orders = await client.orders.list();
  return orders.filter((order) => order.orderStatus === undefined || !TERMINAL_ORDER_STATUSES.has(order.orderStatus)).length;
}

async function countOpenOptionLegs(client: Pick<LiveClient, 'positions'>): Promise<number> {
  const rows = await client.positions.list();
  return rows.filter(
    (row) =>
      (String(row.exchangeSegment) === 'NSE_FNO' || String(row.exchangeSegment) === 'BSE_FNO') &&
      (row.netQty ?? 0) !== 0,
  ).length;
}

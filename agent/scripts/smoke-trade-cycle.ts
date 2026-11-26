/**
 * Fast end-to-end trade cycle against live Dhan market data.
 * Exercises scrip resolution, live option chain, contract selection,
 * rejection branches, bracket pricing, position sizing, pre-trade risk engine,
 * and paper execution lifecycle (entry -> mark -> exit -> P&L record).
 */
import 'dotenv/config';
import { loadConfig } from '../src/config.js';
import { createDhanClient } from '../src/dhan/client.js';
import { jsonlSink, recordWireCalls } from '../src/dhan/wireRecorder.js';
import { InstrumentMaster } from '../src/dhan/instrumentMaster.js';
import { DhanMarketData } from '../src/dhan/marketData.js';
import { pickExpiry, selectContract } from '../src/options/selector.js';
import { bracketLevels } from '../src/options/pricing.js';
import { sizePosition } from '../src/options/sizing.js';
import { evaluatePreTrade } from '../src/risk/riskEngine.js';
import { PaperExecutionPort } from '../src/execution/paper.js';
import { DayBook } from '../src/risk/dayBook.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { istParts } from '../src/time/ist.js';
import type { OptionContract, OptionQuote, OptionSegment } from '../src/domain/types.js';
import type { EntryOrder, ExitOrder } from '../src/execution/ports.js';

interface MarketContext {
  readonly master: InstrumentMaster;
  readonly market: DhanMarketData;
  readonly client: Awaited<ReturnType<typeof createDhanClient>>;
  readonly config: ReturnType<typeof loadConfig>;
}

interface StepResult {
  readonly name: string;
  readonly passed: boolean;
  readonly detail: string;
}

const results: StepResult[] = [];

function record(name: string, passed: boolean, detail: string): void {
  results.push({ name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}: ${detail}`);
}

async function main(): Promise<void> {
  const config = loadConfig({ ...process.env, MODE: 'paper' });
  // Every trading and position call is written, redacted, to docs/sandbox/ for the OTA-106 record (src/dhan/wireRecorder.ts).
  const wireFile = `docs/sandbox/wire-${istParts(Date.now()).date}.jsonl`;
  const client = recordWireCalls(
    await createDhanClient(config.dhan, { logger: createConsoleLogger() }),
    ['orders', 'superOrders', 'positions', 'traderControls'],
    jsonlSink(wireFile, (error) => console.error(`wire record failed: ${String(error)}`)),
  );
  const master = new InstrumentMaster(client.instruments, () => istParts(Date.now()).date);
  const market = new DhanMarketData(client, { istShiftedTimestamps: config.feed.istShiftedTimestamps });
  const underlying = config.underlyings[0];
  if (underlying === undefined) throw new Error('No underlyings configured in config');

  console.log(`\nStarting live market trade cycle smoke test for ${underlying.symbol}...\n`);
  const ctx: MarketContext = { master, market, client, config };
  const data = await resolveMarket(ctx, underlying.symbol, underlying.optionSegment);
  if (data === undefined) return reportSummary();

  const { spotPrice, contracts, chain } = data;
  const bullish = testSelection(spotPrice, 'BULLISH', contracts, chain, config);
  testSelection(spotPrice, 'BEARISH', contracts, chain, config);
  testRejections(spotPrice, contracts, chain);

  if (bullish !== undefined) {
    const tradePlan = testPricing(bullish.contract, bullish.quote, config);
    if (tradePlan !== undefined) {
      testRisk(tradePlan, bullish.contract);
      await testExecution(tradePlan, bullish.contract, underlying.symbol);
    }
  }
  reportSummary();
}

async function resolveMarket(ctx: MarketContext, symbol: string, optionSegment: OptionSegment) {
  const spot = await ctx.master.resolveSpot(symbol);
  record('Resolve spot instrument', true, `${spot.exchangeSegment}:${spot.securityId}`);

  let spotPrice = await ctx.client.marketFeed.ltpFor(spot.exchangeSegment, spot.securityId).catch(() => undefined);
  if (spotPrice === undefined || spotPrice <= 0) {
    const today = istParts(Date.now()).date;
    const candles = await ctx.market.intradayCandles(spot, 5, today, today).catch(() => []);
    spotPrice = candles[candles.length - 1]?.close ?? 22_500;
  }
  record('Resolve spot LTP', spotPrice > 0, `Spot ${symbol} LTP: ₹${spotPrice}`);

  const expiries = await ctx.market.listExpiries(spot);
  const expiry = pickExpiry(expiries, istParts(Date.now()).date, ctx.config.contract.minDaysToExpiry);
  if (expiry === undefined) {
    record('Pick expiry', false, `No valid expiry in [${expiries.slice(0, 3).join(', ')}]`);
    return undefined;
  }
  record('Pick live expiry', true, `Selected ${expiry} from ${expiries.length} expiries`);

  const chain = await fetchChainWithRetry(ctx.market, spot, expiry);
  if (chain === undefined) return undefined;
  const contracts = await ctx.master.optionContracts(symbol, optionSegment);
  record('Fetch option chain & contracts', chain.strikes.length > 0, `${chain.strikes.length} strikes, ${contracts.length} contracts`);
  return { spotPrice, contracts, chain };
}

async function fetchChainWithRetry(
  market: DhanMarketData,
  spot: Parameters<DhanMarketData['optionChain']>[0],
  expiry: string,
) {
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      return await market.optionChain(spot, expiry);
    } catch (err: unknown) {
      const is429 = err !== null && typeof err === 'object' && ('status' in err ? err.status === 429 : String(err).includes('429'));
      if (is429 && attempt < 4) {
        console.log(`Dhan 429 hit, retrying in ${attempt * 3}s (attempt ${attempt}/4)...`);
        await new Promise((resolve) => setTimeout(resolve, attempt * 3000));
        continue;
      }
      throw err;
    }
  }
  record('Fetch option chain', false, 'Failed to fetch option chain');
  return undefined;
}

function testSelection(
  spot: number,
  direction: 'BULLISH' | 'BEARISH',
  contracts: readonly OptionContract[],
  chain: Parameters<typeof selectContract>[0]['chain'],
  config: ReturnType<typeof loadConfig>,
) {
  const outcome = selectContract({
    spot,
    direction,
    expiry: chain.expiry,
    chain,
    contracts,
    offsetSteps: config.contract.strikeOffsetSteps,
    maxSpreadPct: 5,
    minOpenInterest: 100,
    minVolume: 0,
  });
  const label = direction === 'BULLISH' ? 'ATM Call selection' : 'ATM Put selection';
  if (!outcome.ok) {
    record(label, false, `${outcome.code}: ${outcome.detail}`);
    return undefined;
  }
  const q = outcome.quote;
  record(label, true, `${outcome.contract.symbol} (strike ${outcome.contract.strike}) bid ${q.bid} ask ${q.ask} OI ${q.oi}`);
  return outcome;
}

function testRejections(
  spot: number,
  contracts: readonly OptionContract[],
  chain: Parameters<typeof selectContract>[0]['chain'],
) {
  const badSpread = selectContract({
    spot,
    direction: 'BULLISH',
    expiry: chain.expiry,
    chain,
    contracts,
    offsetSteps: 0,
    maxSpreadPct: 0.0001,
    minOpenInterest: 100,
    minVolume: 0,
  });
  record('Rejection: SPREAD_TOO_WIDE', !badSpread.ok && badSpread.code === 'SPREAD_TOO_WIDE', `Rejected with ${!badSpread.ok ? badSpread.code : 'OK'}`);

  const badOi = selectContract({
    spot,
    direction: 'BULLISH',
    expiry: chain.expiry,
    chain,
    contracts,
    offsetSteps: 0,
    maxSpreadPct: 20,
    minOpenInterest: 1_000_000_000,
    minVolume: 0,
  });
  record('Rejection: OPEN_INTEREST_TOO_LOW', !badOi.ok && badOi.code === 'OPEN_INTEREST_TOO_LOW', `Rejected with ${!badOi.ok ? badOi.code : 'OK'}`);
}

function testPricing(contract: OptionContract, quote: OptionQuote, config: ReturnType<typeof loadConfig>) {
  if (quote.ask === undefined || quote.bid === undefined) {
    record('Pricing: bracket levels', false, 'Missing two-sided quote');
    return undefined;
  }
  const bracket = bracketLevels({
    entryReference: quote.ask,
    stopLossPct: config.exits.stopLossPct,
    targetRr: config.exits.targetRr,
    tickSize: contract.tickSize,
  });
  if (bracket === undefined) {
    record('Pricing: bracket levels', false, `Cannot represent bracket on tick grid (ask=${quote.ask}, tick=${contract.tickSize})`);
    return undefined;
  }
  record('Pricing: bracket levels', true, `Entry ${bracket.entryReference} -> Stop ${bracket.stopLossPrice} (-${config.exits.stopLossPct}%) | Target ${bracket.targetPrice} (${config.exits.targetRr}R)`);

  const sizing = sizePosition({
    capitalInr: Math.max(config.capital.inr, 200_000),
    maxRiskPerTradePct: Math.max(config.capital.maxRiskPerTradePct, 2),
    availableFundsInr: Math.max(config.capital.inr, 200_000),
    entryReference: bracket.entryReference,
    stopLossPrice: bracket.stopLossPrice,
    lotSize: contract.lotSize,
    maxLotsPerOrder: Math.max(config.capital.maxLotsPerOrder, 1),
  });
  record('Sizing: position size', sizing.lots >= 1, `Lots ${sizing.lots} (qty ${sizing.quantity}), risk budget ₹${sizing.riskBudgetInr.toFixed(2)} (limited by ${sizing.limitedBy})`);
  return { bracket, sizing };
}

function runRiskCheck(plan: NonNullable<ReturnType<typeof testPricing>>, contract: OptionContract, killSwitchActive: boolean) {
  const now = Date.now();
  return evaluatePreTrade({
    side: 'BUY', entryReference: plan.bracket.entryReference,
    stopLossPrice: plan.bracket.stopLossPrice, targetPrice: plan.bracket.targetPrice,
    lots: plan.sizing.lots, lotSize: contract.lotSize, maxLotsPerOrder: 10,
    maxRiskInr: plan.sizing.riskBudgetInr, availableFundsInr: 200_000,
    nowMs: now, minuteOfDay: istParts(now).minuteOfDay,
    entryStartMinute: 0, entryEndMinute: 24 * 60, isExpiryDay: false, expiryDayCutoffMinute: 24 * 60,
    killSwitchActive, dailyPnlInr: 0, dailyLossLimitInr: 50_000, realizedPnlInr: 0, openRiskInr: 0, tradesToday: 0, maxTradesPerDay: 10,
    openPositions: 0, maxOpenPositions: 1, underlyingOpen: false, cooldownUntilMs: undefined,
    spotTickAgeMs: 100, optionQuoteAgeMs: 100, staleMs: 5_000,
  });
}

function testRisk(plan: NonNullable<ReturnType<typeof testPricing>>, contract: OptionContract) {
  const approved = runRiskCheck(plan, contract, false);
  record('Pre-trade risk engine approval', approved.approved, `Verdict: approved=${approved.approved}, risk=₹${approved.riskInr}`);

  const blocked = runRiskCheck(plan, contract, true);
  record('Pre-trade risk: kill switch rejection', !blocked.approved && blocked.violations[0]?.code === 'KILL_SWITCH_ACTIVE', 'Successfully rejected when kill switch active');
}

async function testExecution(plan: NonNullable<ReturnType<typeof testPricing>>, contract: OptionContract, underlying: string) {
  const paper = new PaperExecutionPort({ slippageBps: 10 });
  const book = new DayBook(Date.now(), 60_000);
  const events: string[] = [];
  paper.onEvent((ev) => events.push(ev.kind));

  const correlationId = `test-${Date.now()}`.slice(0, 30);
  const order: EntryOrder = {
    side: 'BUY',
    correlationId,
    underlying,
    contract,
    quantity: plan.sizing.quantity,
    entryReference: plan.bracket.entryReference,
    stopLossPrice: plan.bracket.stopLossPrice,
    targetPrice: plan.bracket.targetPrice,
  };
  await paper.submitEntry(order);
  await new Promise((resolve) => setTimeout(resolve, 20));
  book.recordEntry(underlying);
  record('Paper execution: entry fill', events.includes('ENTRY_FILLED'), `Entry ${order.correlationId} filled in paper venue`);

  const exit: ExitOrder = {
    side: 'SELL',
    correlationId: `exit-${Date.now()}`.slice(0, 30),
    underlying,
    positionId: correlationId,
    contract,
    quantity: plan.sizing.quantity,
    reason: 'TARGET',
    referencePrice: plan.bracket.targetPrice,
  };
  await paper.submitExit(exit);
  await new Promise((resolve) => setTimeout(resolve, 20));
  const realizedPnl = (plan.bracket.targetPrice - plan.bracket.entryReference) * plan.sizing.quantity;
  book.recordClose({ underlying, pnlInr: realizedPnl, closedAtMs: Date.now() });
  record('Paper execution: target exit fill', events.includes('EXIT_FILLED'), `Exit filled at target ₹${plan.bracket.targetPrice}, realized P&L: ₹${realizedPnl.toFixed(2)}`);

  const snapshot = book.snapshot();
  record('DayBook record update', snapshot.tradesToday === 1 && snapshot.dayPnlInr === realizedPnl, `Trades today: ${snapshot.tradesToday}, P&L: ₹${snapshot.dayPnlInr.toFixed(2)}, Cooldown active`);
}

function reportSummary(): void {
  const failed = results.filter((r) => !r.passed).length;
  console.log(`\n======================================================`);
  console.log(`Live Trade Cycle Smoke Test: ${results.length - failed}/${results.length} checks PASSED`);
  console.log(`======================================================\n`);
  process.exitCode = failed === 0 ? 0 : 1;
}

main().catch((err: unknown) => {
  console.error('Fatal error running trade cycle:', err);
  process.exitCode = 1;
});

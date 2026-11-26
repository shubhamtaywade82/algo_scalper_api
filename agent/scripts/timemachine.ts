/**
 * Time Machine: offline historical replay of the live strategy on real option premiums, with a block bootstrap
 * and Monte Carlo paths over the replayed days. Research only. It imports no order code and never touches the
 * live risk gate.
 *
 *   # 1. Build a dataset (read-only Dhan calls: intraday spot bars + /charts/rollingoption)
 *   npm run timemachine -- fetch --underlying NIFTY --from 2026-04-01 --to 2026-09-30 --lot-size 75
 *        [--expiry-flag WEEK] [--expiry-code 1] [--offsets 10] [--tick-size 0.05] [--spacing-ms 400]
 *        [--timeout-ms 30000] [--out data/research/NIFTY-2026-04-01-2026-09-30.json] [--dump-raw] [--window-days 30]
 *
 *   # 2. Replay it with the current config (no credentials, no network)
 *   npm run timemachine -- run --data data/research/NIFTY-2026-04-01-2026-09-30.json
 *        [--config config.paper.yml] [--seed 19] [--iterations 10000] [--horizon 20] [--split 0.6]
 *        [--half-spread-pct 1] [--stop-slippage-pct 1] [--drawdown-alarm 30000] [--json] [--trades trades.csv]
 *
 *   # 3. Replay several indices as one account (shared daily limit, per-side and open-position caps)
 *   npm run timemachine -- portfolio --data A.json,B.json,C.json [--config config.paper.yml] [--per-side 1]
 *
 * Split a fetch at every lot-size change: one dataset carries one lot size per range.
 */
import 'dotenv/config';
import { createHash } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { configFingerprint, loadConfig, KNOWN_UNDERLYINGS, type AgentConfig } from '../src/config.js';
import type { Candle, OptionType } from '../src/domain/types.js';
import { applyCostStressToCells, contextCells, formatCells, vixTerciles, type CellReport } from '../src/research/contextCells.js';
import { costsFingerprint, overlapGroupFor, priorVariantCount, UNKNOWN, type ExperimentType, type HoldoutStatus, type LedgerBody } from '../src/research/experimentLedger.js';
import { appendToLedgerFile, LEDGER_PATH, readLedgerFile } from '../src/research/ledgerStore.js';
import {
  buildSessions,
  parseDataset,
  parseRollingOptionResponse,
  pivotByStrike,
  ROLLING_PARSER_VERSION,
  ROLLING_RESPONSE_SCHEMA_VERSION,
  type ResearchDataset,
  type RollingBar,
} from '../src/research/dataset.js';
import { simulatePortfolio, type PortfolioTrade } from '../src/research/portfolio.js';
import { defaultCostModel, replayConfigFrom, replayDataset, type CostModel, type ReplayConfig } from '../src/research/replay.js';
import { createShadowTally, shadowObserver } from '../src/research/shadow.js';
import { atBarMinutes } from '../src/research/studyEntries.js';
import { STRATEGY_CATALOG, type StrategyId } from '../src/strategy/session.js';
import { summarize } from '../src/research/stats.js';
import { applyCostStress, DEFAULT_TIME_MACHINE_OPTIONS, formatReport, runTimeMachine, type CostStressRun, type TimeMachineReport } from '../src/research/timeMachine.js';
import { shiftDateKey } from '../src/time/ist.js';
import { requestBlocks, ROLLING_EXPIRY_CODES, ROLLING_MAX_SPAN_DAYS, rollingRequest, type RollingInterval } from '../src/research/rollingFetch.js';

/** Dhan's intraday chart window is 90 days and the rolling-option one 180; 30-day windows stay well inside both. */
/**
 * Every replay is another test on the same days; the best of k variants is optimistic by about a factor of k.
 * This log keeps k countable per dataset.
 */
const RUN_LOG = 'data/research/runs.jsonl';

/** The exact SDK the fetch actually loaded, read from the installed package, not from the declared range. */
function installedSdkVersion(): string {
  const manifest = fileURLToPath(new URL('../node_modules/@nemesis-oss/dhanhq-sdk/package.json', import.meta.url));
  return (JSON.parse(readFileSync(manifest, 'utf8')) as { version: string }).version;
}
/**
 * Which verdict rules produced a line. v1 used 20 holdout sessions and no best-session test. v2 uses 30 sessions, removes
 * the single best session, and blocks the holdout bootstrap in at least five sessions. v3 also caps one session's share of profit,
 * and uses the look-ahead-free expiry. v1 and v2 results are not comparable to v3.
 */
const HOLDOUT_RULES = 'holdout-v4';
const MAX_ATTEMPTS = 3;

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function flag(name: string): boolean {
  return process.argv.includes(name);
}

function required(name: string): string {
  const value = argument(name);
  if (value === undefined) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function dateArgument(name: string): string {
  const value = required(name);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${name} must be YYYY-MM-DD, got "${value}"`);
  }
  return value;
}

function numberArgument(name: string, fallback: number, check: (value: number) => boolean): number {
  const text = argument(name);
  if (text === undefined) {
    return fallback;
  }
  const value = Number(text);
  if (!Number.isFinite(value) || !check(value)) {
    throw new Error(`${name} is out of range: "${text}"`);
  }
  return value;
}


const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

async function withRetry<T>(label: string, run: () => Promise<T>): Promise<T> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      return await run();
    } catch (error) {
      lastError = error;
      const err = error as { message?: string; payload?: unknown; details?: unknown };
      const extra = err.details ? ` (${JSON.stringify(err.details)})` : err.payload ? ` (${JSON.stringify(err.payload)})` : '';
      const message = `${err.message ?? String(error)}${extra}`;
      console.error(`${label}: attempt ${attempt}/${MAX_ATTEMPTS} failed: ${message}`);
      if (attempt < MAX_ATTEMPTS) {
        await sleep(1_000 * 2 ** attempt);
      }
    }
  }
  throw new Error(`${label}: gave up after ${MAX_ATTEMPTS} attempts (${lastError instanceof Error ? lastError.message : String(lastError)})`);
}

async function fetchDataset(): Promise<void> {
  const underlying = required('--underlying').toUpperCase();
  const optionSegment = KNOWN_UNDERLYINGS[underlying];
  if (optionSegment === undefined) {
    throw new Error(`unknown underlying ${underlying}; known: ${Object.keys(KNOWN_UNDERLYINGS).join(', ')}`);
  }
  const fromDate = dateArgument('--from');
  const toDate = dateArgument('--to');
  if (fromDate > toDate) {
    throw new Error('--from must not be after --to');
  }
  const lotSize = numberArgument('--lot-size', Number.NaN, (value) => Number.isInteger(value) && value > 0);
  if (Number.isNaN(lotSize)) {
    throw new Error('--lot-size is required: lot sizes change, so the one in force over the range must be given');
  }
  const tickSize = numberArgument('--tick-size', 0.05, (value) => value > 0);
  const barMinutes = numberArgument('--interval', 5, (value) => [1, 5, 15, 25, 60].includes(value));
  const intervalText = String(barMinutes) as RollingInterval;
  const offsets = numberArgument('--offsets', 10, (value) => Number.isInteger(value) && value >= 0 && value <= 10);
  const expiryCode = numberArgument('--expiry-code', 1, (value) => ROLLING_EXPIRY_CODES.includes(value)) as 0 | 1 | 2;
  const expiryFlag = (argument('--expiry-flag') ?? 'WEEK').toUpperCase();
  if (expiryFlag !== 'WEEK' && expiryFlag !== 'MONTH') {
    throw new Error('--expiry-flag must be WEEK or MONTH');
  }
  const spacingMs = numberArgument('--spacing-ms', 400, (value) => value >= 0);
  const timeoutMs = numberArgument('--timeout-ms', 30_000, (value) => value > 0);
  const out = argument('--out') ?? `data/research/${underlying}-${fromDate}-${toDate}.json`;

  const { createDhanClient } = await import('../src/dhan/client.js');
  const { InstrumentMaster } = await import('../src/dhan/instrumentMaster.js');
  const { DhanMarketData } = await import('../src/dhan/marketData.js');
  const { createConsoleLogger } = await import('../src/ops/logger.js');
  const { istParts } = await import('../src/time/ist.js');

  const config = loadConfig({ ...process.env, MODE: 'paper' });
  const client = await createDhanClient(config.dhan, { logger: createConsoleLogger(), timeoutMs });
  const master = new InstrumentMaster(client.instruments, () => istParts(Date.now()).date);
  const market = new DhanMarketData(client, { istShiftedTimestamps: config.feed.istShiftedTimestamps });
  const spotRef = await master.resolveSpot(underlying);

  const spot: Candle[] = [];
  const rolling: Record<OptionType, RollingBar[][]> = { CE: [], PE: [] };
  const dumped = new Set<OptionType>();
  // Dhan began refusing 1-minute rolling-option requests that span more than one session (HTTP 400, seen
  // 2026-11-03; 30-day windows worked on 2026-10-26). `--window-days 1` fetches one session per request.
  const defaultWindowDays = barMinutes === 1 ? 1 : ROLLING_MAX_SPAN_DAYS;
  const windowDays = numberArgument('--window-days', defaultWindowDays, (value) => Number.isInteger(value) && value >= 1 && value <= ROLLING_MAX_SPAN_DAYS);
  for (const window of requestBlocks(fromDate, toDate, windowDays)) {
    console.error(`${underlying} ${window.from}..${window.to}: spot bars`);
    spot.push(...(await withRetry(`spot ${window.from}`, () => market.intradayCandles(spotRef, barMinutes, window.from, window.to))));
    for (const optionType of ['CE', 'PE'] as const) {
      for (let offset = -offsets; offset <= offsets; offset += 1) {
        const strike = offset === 0 ? 'ATM' : offset > 0 ? `ATM+${offset}` : `ATM${offset}`;
        await sleep(spacingMs);
        const raw = await withRetry(`${optionType} ${strike} ${window.from}`, () =>
          client.expiredOptionsData.fetch(
            rollingRequest({
              securityId: spotRef.securityId,
              exchangeSegment: optionSegment,
              expiryFlag,
              expiryCode,
              strike,
              drvOptionType: optionType === 'CE' ? 'CALL' : 'PUT',
              interval: intervalText,
              requiredData: ['open', 'high', 'low', 'close', 'volume', 'strike', 'iv', 'oi'],
              block: window,
            }),
          ),
        );
        if (flag('--dump-raw') && !dumped.has(optionType)) {
          dumped.add(optionType);
          const rawPath = `${out}.raw-${optionType}.json`;
          await mkdir(dirname(rawPath), { recursive: true });
          await writeFile(rawPath, JSON.stringify(raw, null, 2));
          console.error(`raw ${optionType} response written to ${rawPath}`);
        }
        rolling[optionType].push(parseRollingOptionResponse(raw, optionType, config.feed.istShiftedTimestamps));
      }
    }
  }

  const calls = pivotByStrike(rolling.CE);
  const puts = pivotByStrike(rolling.PE);
  const uniqueSpot = [...new Map(spot.map((bar) => [bar.time, bar])).values()].sort((a, b) => a.time - b.time);
  const dataset: ResearchDataset = {
    version: 1,
    underlying,
    optionSegment,
    barMinutes,
    source: {
      kind: 'dhan_rollingoption',
      expiryFlag,
      expiryCode,
      offsets,
      fetchedAt: new Date().toISOString(),
      conflictingBars: calls.conflicts + puts.conflicts,
      provenance: { sdkVersion: installedSdkVersion(), parserVersion: ROLLING_PARSER_VERSION, responseSchemaVersion: ROLLING_RESPONSE_SCHEMA_VERSION },
    },
    sessions: buildSessions({ spot: uniqueSpot, calls: calls.byStrike, puts: puts.byStrike, lotSize, tickSize, fromDate, toDate }),
  };
  // Round-trip through the validator so a file on disk is always one `run` accepts.
  parseDataset(JSON.parse(JSON.stringify(dataset)));
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, JSON.stringify(dataset));
  console.log(`wrote ${out}: ${dataset.sessions.length} sessions, ${dataset.source.conflictingBars} conflicting bars`);
}

/** The replay never calls the broker. Placeholders satisfy config validation without real credentials. */
function offlineConfig(configPath: string | undefined): AgentConfig {
  const env: Record<string, string | undefined> = { ...process.env, MODE: 'paper' };
  env.DHAN_CLIENT_ID ??= 'offline-research';
  if (env.DHAN_ACCESS_TOKEN === undefined && env.DHAN_PIN === undefined && env.DHAN_TOTP_SECRET === undefined) {
    env.DHAN_ACCESS_TOKEN = 'offline-research';
  }
  env.DATABASE_URL ??= 'postgres://offline-research@127.0.0.1:5432/offline_research';
  return loadConfig(env, configPath);
}

function costsArgument(config: AgentConfig): CostModel {
  const fallbackCosts = defaultCostModel(config);
  return {
    halfSpreadPct: numberArgument('--half-spread-pct', fallbackCosts.halfSpreadPct, (value) => value >= 0 && value <= 20),
    stopSlippagePct: numberArgument('--stop-slippage-pct', fallbackCosts.stopSlippagePct, (value) => value >= 0 && value <= 20),
  };
}

async function runReplay(): Promise<void> {
  const dataPath = required('--data');
  const configPath = argument('--config');
  const config = offlineConfig(configPath);
  const dataText = await readFile(dataPath, 'utf8');
  const { replay: configured, divergences } = replayConfigFrom(config);
  const replay = strategyOverride(configured, argument('--strategy'));
  const dataset = atBarMinutes(parseDataset(JSON.parse(dataText)), replay.barMinutes);
  const costs = costsArgument(config);
  const options = {
    ...DEFAULT_TIME_MACHINE_OPTIONS,
    seed: numberArgument('--seed', DEFAULT_TIME_MACHINE_OPTIONS.seed, (value) => Number.isInteger(value) && value >= 0 && value < 2 ** 32),
    iterations: numberArgument('--iterations', DEFAULT_TIME_MACHINE_OPTIONS.iterations, (value) => Number.isInteger(value) && value >= 100 && value <= 1_000_000),
    horizonDays: numberArgument('--horizon', DEFAULT_TIME_MACHINE_OPTIONS.horizonDays, (value) => Number.isInteger(value) && value >= 1),
    splitFraction: numberArgument('--split', DEFAULT_TIME_MACHINE_OPTIONS.splitFraction, (value) => value > 0 && value < 1),
    drawdownAlarmInr: numberArgument('--drawdown-alarm', (config.capital.inr * config.capital.maxDailyLossPct) / 100, (value) => value > 0),
  };
  const baseReport = runTimeMachine(dataset, replay, costs, divergences, options);
  // The verdict must survive every stressed cost model before it can stand (OTA-308).
  const stresses: CostStressRun[] = stressScenarios(costs).map(({ label, costs: stressed }) => ({
    label,
    report: runTimeMachine(dataset, replay, stressed, divergences, options),
  }));
  const report = applyCostStress(baseReport, stresses);
  const tradesPath = argument('--trades');
  if (tradesPath !== undefined) {
    const header = 'date,strategy,direction,optionType,strike,entryTime,exitTime,entryPrice,exitPrice,lots,quantity,riskInr,grossPnlInr,chargesInr,netPnlInr,r,exitReason,ambiguousBar,gapThroughStop';
    const rows = report.trades.map((t) =>
      [t.date, t.strategy, t.direction, t.optionType, t.strike, new Date(t.entryTime).toISOString(), new Date(t.exitTime).toISOString(), t.entryPrice, t.exitPrice, t.lots, t.quantity, t.riskInr, t.grossPnlInr, t.chargesInr, t.netPnlInr, t.r, t.exitReason, t.ambiguousBar, t.gapThroughStop].join(','),
    );
    await writeFile(tradesPath, [header, ...rows].join('\n') + '\n');
  }
  const dataSha256 = createHash('sha256').update(dataText).digest('hex');
  const cellsBase = flag('--cells') ? await cellReport(baseReport, dataset) : undefined;
  const cells =
    cellsBase === undefined
      ? undefined
      : applyCostStressToCells(
          cellsBase,
          await Promise.all(stresses.map(async (stress) => ({ label: stress.label, report: await cellReport(stress.report, dataset) }))),
        );
  const run = {
    ts: new Date().toISOString(),
    data: dataPath,
    // The path alone does not identify the data: a re-fetch overwrites the file.
    dataSha256,
    dataQuality: report.dataQuality,
    config: configPath ?? null,
    rules: HOLDOUT_RULES,
    strategy: argument('--strategy') ?? null,
    configFingerprint: configFingerprint(config),
    costs,
    trades: report.overall.trades,
    meanR: report.overall.meanR,
    verdict: report.verdict,
    // Rejected signals are part of the record, not only the printed report: a run that drops most of its signals is different evidence.
    signals: report.signals,
    drops: report.drops,
    ...(cells === undefined
      ? {}
      : { cells: { tests: cells.testsCounted, edge: cells.cells.filter((cell) => cell.verdict === 'EDGE_SUPPORTED').map((cell) => cell.key) } }),
  };
  // The ledger record is written before the local log line. A refused run (for example, a confirmation without a registration) writes neither.
  const range = { from: report.fromDate ?? null, to: report.toDate ?? null, label: argument('--label') ?? null };
  const existing = await readLedgerFile(LEDGER_PATH);
  const ledgerBody: LedgerBody = {
    record_kind: 'experiment',
    hypothesis_id: argument('--hypothesis') ?? null,
    strategy_id: argument('--strategy') ?? 'configured-set',
    parameter_fingerprint: configFingerprint(config),
    dataset_hash: dataSha256,
    underlying: dataset.underlying,
    date_range: range,
    overlap_group: overlapGroupFor(existing, dataset.underlying, range),
    experiment_type: (argument('--type') ?? 'discovery') as ExperimentType,
    holdout_status: (argument('--holdout') ?? 'NotHoldout') as HoldoutStatus,
    cells: cells?.cells.length ?? 0,
    variants_evaluated: 1,
    costs_fingerprint: costsFingerprint(costs),
    provenance: provenanceOf(dataset),
    result: {
      verdict: report.verdict,
      meanR: report.overall.meanR,
      trades: report.overall.trades,
      signals: report.signals,
      rejections: report.drops,
      holdoutTrades: report.outOfSample.trades,
      holdoutInterval95: report.bootstrap?.meanRCi95 ?? null,
      costStress: stresses.map((stress) => ({ label: stress.label, verdict: stress.report.verdict })),
      cellsEdge: cells === undefined ? null : cells.cells.filter((cell) => cell.verdict === 'EDGE_SUPPORTED').length,
      testsCounted: cells?.testsCounted ?? null,
      evidence_id: `run:${run.ts}:${dataSha256}`,
      rules: HOLDOUT_RULES,
    },
    source: 'scripts/timemachine.ts run',
    created_at: run.ts,
  };
  await appendToLedgerFile(LEDGER_PATH, ledgerBody);
  await mkdir(dirname(RUN_LOG), { recursive: true });
  await appendFile(RUN_LOG, `${JSON.stringify(run)}\n`);
  console.log(flag('--json') ? JSON.stringify(report, null, 2) : formatReport(report));
  if (flag('--shadow')) {
    const tally = createShadowTally();
    replayDataset(dataset, replay, costs, divergences, shadowObserver(tally));
    console.log(`\nShadow: ${tally.entryBars} entry bars, ${tally.multiSignalBars} with two or more families signalling`);
    console.log(`  credited by first-match: ${JSON.stringify(tally.credited)}`);
    console.log(`  hidden by first-match:   ${JSON.stringify(tally.hidden)}`);
  }
  if (cells !== undefined) {
    console.log(`\n${formatCells(cells)}`);
  }
}

/**
 * `--strategy <id>` replays one family alone, so the catalogue order cannot decide which family is credited (OTA-307).
 * The live engine is unaffected: this only changes the research replay.
 */
function strategyOverride(replay: ReplayConfig, id: string | undefined): ReplayConfig {
  if (id === undefined) {
    return replay;
  }
  if (!STRATEGY_CATALOG.some((row) => row.id === id)) {
    throw new Error(`unknown strategy "${id}"; known: ${STRATEGY_CATALOG.map((row) => row.id).join(', ')}`);
  }
  return { ...replay, enabledStrategies: [id as StrategyId] };
}

/**
 * The cost stresses a verdict must survive (OTA-308): a 1% half-spread, and twice the stop slippage. Each is at least
 * the base cost, so a stress can only make the test harder.
 */
function stressScenarios(base: CostModel): { label: string; costs: CostModel }[] {
  return [
    { label: 'half-spread 1%', costs: { ...base, halfSpreadPct: Math.max(1, base.halfSpreadPct), stopSlippagePct: Math.max(1, base.stopSlippagePct) } },
    { label: 'stop slippage 2x', costs: { ...base, stopSlippagePct: 2 * base.stopSlippagePct } },
  ];
}

/**
 * Every variant evaluated before this run, read from the committed ledger. The ledger is hash-chained, so a broken or
 * edited ledger throws here and no divisor is taken from it (docs/research/experiments.jsonl).
 */
/** A dataset's recorded provenance, or UNKNOWN for datasets fetched before it was recorded. */
function provenanceOf(dataset: ResearchDataset): { sdk_version: string; parser_version: string; response_schema_version: string } {
  const provenance = dataset.source.provenance;
  return {
    sdk_version: provenance?.sdkVersion ?? UNKNOWN,
    parser_version: provenance?.parserVersion ?? UNKNOWN,
    response_schema_version: provenance?.responseSchemaVersion ?? UNKNOWN,
  };
}

async function priorVariants(): Promise<number> {
  return priorVariantCount(await readLedgerFile(LEDGER_PATH));
}

/** Per-strategy, per-context cells for `run --cells`: `--vix <file>` adds the VIX tercile per day, `--iv` the entry's ATM IV bucket. */
async function cellReport(report: TimeMachineReport, dataset: ResearchDataset): Promise<CellReport> {
  const dates = dataset.sessions.map((session) => session.date);
  const vixPath = argument('--vix');
  const dayTags = vixPath === undefined ? new Map() : vixTerciles(JSON.parse(await readFile(vixPath, 'utf8')) as Candle[], dates);
  return contextCells({ trades: report.trades, dates }, dayTags, {
    iterations: numberArgument('--iterations', DEFAULT_TIME_MACHINE_OPTIONS.iterations, (value) => Number.isInteger(value) && value >= 100 && value <= 1_000_000),
    seed: DEFAULT_TIME_MACHINE_OPTIONS.seed,
    minTrades: DEFAULT_TIME_MACHINE_OPTIONS.minTrades,
    splitFraction: DEFAULT_TIME_MACHINE_OPTIONS.splitFraction,
    minHoldoutDays: DEFAULT_TIME_MACHINE_OPTIONS.minHoldoutDays,
    includeIv: flag('--iv'),
    priorRuns: await priorVariants(),
  });
}

/**
 * Replays several indices under one account: each index runs with no daily limit, then the shared daily limit
 * and the per-side and open-position caps are applied across them on one timeline.
 */
async function runPortfolio(): Promise<void> {
  const dataPaths = required('--data').split(',');
  const config = offlineConfig(argument('--config'));
  const costs = costsArgument(config);
  const { replay } = replayConfigFrom(config);
  const unlimited = { ...replay, capital: { ...replay.capital, maxDailyLossPct: 100 } };
  const trades: PortfolioTrade[] = [];
  const dates = new Set<string>();
  for (const dataPath of dataPaths) {
    const dataset = atBarMinutes(parseDataset(JSON.parse(await readFile(dataPath, 'utf8'))), replay.barMinutes);
    const result = replayDataset(dataset, unlimited, costs);
    result.dates.forEach((date) => dates.add(date));
    trades.push(...result.trades.filter((trade) => trade.exitReason !== 'DATA_GAP').map((trade) => ({ ...trade, underlying: dataset.underlying })));
  }
  const rules = {
    dailyLossLimitInr: (config.capital.inr * config.capital.maxDailyLossPct) / 100,
    maxPositionsPerSide: numberArgument('--per-side', config.capital.maxPositionsPerSide, (value) => Number.isInteger(value) && value >= 1),
    maxOpenPositions: config.capital.maxOpenPositions,
  };
  const { taken, skipped } = simulatePortfolio(trades, rules);
  const summary = summarize([...taken].sort((a, b) => a.exitTime - b.exitTime), dates.size);
  console.log(`Portfolio: ${dataPaths.length} indices, ${dates.size} days, per side ${rules.maxPositionsPerSide}, open ${rules.maxOpenPositions}, daily limit ₹${rules.dailyLossLimitInr}`);
  console.log(`  trades ${summary.trades} of ${trades.length}; skipped ${JSON.stringify(skipped)}`);
  console.log(`  total net ₹${summary.totalNetInr.toFixed(0)}, mean net R ${summary.meanR}, win rate ${summary.winRate}, profit factor ${summary.profitFactor}, max drawdown ₹${summary.maxDrawdownInr.toFixed(0)}`);
}

async function main(): Promise<void> {
  const command = process.argv[2];
  if (command === 'fetch') {
    await fetchDataset();
  } else if (command === 'run') {
    await runReplay();
  } else if (command === 'portfolio') {
    await runPortfolio();
  } else {
    throw new Error('usage: npm run timemachine -- fetch|run|portfolio [options] (see scripts/timemachine.ts)');
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});

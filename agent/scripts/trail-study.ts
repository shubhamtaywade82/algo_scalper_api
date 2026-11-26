/**
 * Trailing-stop study (docs/TRAILING_STOPS.md): replays every configuration in the study grid over the same frozen
 * entries and compares each with the production exit (B1). Research only: no order code, no network.
 *
 *   npm run trail-study -- --data data/research/NIFTY-….json,data/research/BANKNIFTY-….json
 *        [--config config.paper.yml] [--target none|keep] [--max-hold 20] [--half-spread-pct 1] [--stop-slippage-pct 1]
 *        [--vix data/research/INDIAVIX-5m-….json] [--holdout-from 2026-08] [--holdout] [--train-months 4]
 *        [--iterations 2000] [--seed 19] [--json out.json]
 *
 * Without --holdout the months from --holdout-from on are excluded. --holdout runs on those months only, once.
 */
import 'dotenv/config';
import { createHash } from 'node:crypto';
import { appendFile, readFile, writeFile } from 'node:fs/promises';
import { loadConfig, type AgentConfig } from '../src/config.js';
import type { Candle } from '../src/domain/types.js';
import { specId } from '../src/exits/trail.js';
import { vixTerciles } from '../src/research/contextCells.js';
import { parseDataset, type ResearchDataset } from '../src/research/dataset.js';
import { defaultCostModel, replayConfigFrom, replayDataset, type CostModel, type ReplayConfig, type ReplayTrade } from '../src/research/replay.js';
import { STUDY_GRID } from '../src/research/trailGrid.js';
import { capture, dailyDeltas, dayNetDeltas, holm, pairedBootstrap, realityCheck, walkForward, type PolicyTrades } from '../src/research/trailStats.js';
import { aggregateDataset, atBarMinutes, fineBarsFor, freezeEntries } from '../src/research/studyEntries.js';
import type { TrailSpec } from '../src/exits/trail.js';
import { exitPath, type StudyEntry, type StudyOptions, type StudyTrade } from '../src/research/trailStudy.js';

const RUN_LOG = 'data/research/runs.jsonl';

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function numberArgument(name: string, fallback: number): number {
  const text = argument(name);
  const value = text === undefined ? fallback : Number(text);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number, got "${text}"`);
  }
  return value;
}

function offlineConfig(configPath: string | undefined): AgentConfig {
  const env: Record<string, string | undefined> = { ...process.env, MODE: 'paper' };
  env.DHAN_CLIENT_ID ??= 'offline-research';
  if (env.DHAN_ACCESS_TOKEN === undefined && env.DHAN_PIN === undefined && env.DHAN_TOTP_SECRET === undefined) {
    env.DHAN_ACCESS_TOKEN = 'offline-research';
  }
  env.DATABASE_URL ??= 'postgres://offline-research@127.0.0.1:5432/offline_research';
  return loadConfig(env, configPath);
}

interface Loaded {
  readonly entries: StudyEntry[];
  readonly dates: string[];
  readonly hashes: string[];
  /** Baseline trades the fixed-entry path did not reproduce; must be 0 for the study to be trusted. */
  readonly mismatches: number;
  readonly datasets: ResearchDataset[];
}

async function loadEntries(paths: readonly string[], replay: ReplayConfig, costs: CostModel, keepMonth: (month: string) => boolean): Promise<Loaded> {
  const entries: StudyEntry[] = [];
  const dates = new Set<string>();
  const hashes: string[] = [];
  const datasets: ResearchDataset[] = [];
  let mismatches = 0;
  for (const path of paths) {
    const text = await readFile(path, 'utf8');
    hashes.push(createHash('sha256').update(text).digest('hex'));
    const dataset = atBarMinutes(parseDataset(JSON.parse(text)), replay.barMinutes);
    datasets.push(dataset);
    const frozen = freezeEntries(dataset, replayDataset(dataset, replay, costs).trades, replay.warmupSessions);
    for (const entry of frozen.filter((e) => e.trade.exitReason !== 'DAILY_LOSS')) {
      const again = exitPath(entry, { kind: 'B1' }, { target: 'KEEP', structureExit: replay.structureExit }, replay, costs);
      mismatches += again.exitTime === entry.trade.exitTime && again.exitPrice === entry.trade.exitPrice ? 0 : 1;
    }
    entries.push(...frozen.filter((entry) => keepMonth(entry.trade.date.slice(0, 7))));
    dataset.sessions.map((session) => session.date).filter((date) => keepMonth(date.slice(0, 7))).forEach((date) => dates.add(date));
  }
  return { entries, dates: [...dates].sort(), hashes, mismatches, datasets };
}

async function priorRuns(hashes: readonly string[]): Promise<number> {
  const text = await readFile(RUN_LOG, 'utf8').catch(() => '');
  const key = [...hashes].sort().join(',');
  return text.split('\n').filter((line) => line.includes('"kind":"trail-study"') && line.includes(key)).length;
}

interface Row {
  readonly id: string;
  readonly capture: number | undefined;
  readonly meanDelta: number;
  readonly ci95: { low: number; high: number };
  readonly p: number;
  readonly pHolm: number;
  readonly indexSigns: string;
  readonly trailExitShare: number;
  readonly fallbackShare: number;
}

function signsByIndex(entries: readonly StudyEntry[], baseline: readonly StudyTrade[], trades: readonly StudyTrade[]): string {
  const byIndex = new Map<string, number>();
  entries.forEach((entry, i) => {
    const key = entry.underlying;
    byIndex.set(key, (byIndex.get(key) ?? 0) + (trades[i]?.netPnlInr ?? 0) - (baseline[i]?.netPnlInr ?? 0));
  });
  return [...byIndex.entries()].map(([key, delta]) => `${key[0]}${delta >= 0 ? '+' : '−'}`).join('');
}

function rowsFor(loaded: Loaded, baseline: readonly StudyTrade[], policies: readonly PolicyTrades[], options: { iterations: number; seed: number; runs: number }): Row[] {
  const results = policies.map((policy) => ({ policy, paired: pairedBootstrap(dailyDeltas(loaded.dates, baseline, policy.trades), options) }));
  // Every earlier study run on the same data was another search over it: Bonferroni across runs, Holm within this one.
  const adjusted = holm(results.map((r) => Math.min(1, r.paired.pNonPositive * options.runs)));
  return results.map(({ policy, paired }, i) => ({
    id: policy.id,
    capture: capture(policy.trades),
    meanDelta: paired.meanDelta,
    ci95: paired.ci95,
    p: paired.pNonPositive,
    pHolm: adjusted[i] ?? 1,
    indexSigns: signsByIndex(loaded.entries, baseline, policy.trades),
    trailExitShare: policy.trades.filter((t) => t.exitReason === 'TRAILING_STOP').length / Math.max(1, policy.trades.length),
    fallbackShare: policy.trades.filter((t) => t.trailFallback !== undefined).length / Math.max(1, policy.trades.length),
  }));
}

const pct = (value: number | undefined): string => (value === undefined ? '   n/a' : `${(value * 100).toFixed(1).padStart(6)}%`);
const num = (value: number): string => value.toFixed(4).padStart(8);

function formatRows(rows: readonly Row[], baselineCapture: number | undefined): string {
  const header = `${'policy'.padEnd(72)} capture   meanΔR      95% CI            p     pHolm  idx  trail%  fallback%`;
  const lines = [...rows]
    .sort((a, b) => (b.capture ?? -Infinity) - (a.capture ?? -Infinity))
    .map((r) => `${r.id.slice(0, 72).padEnd(72)} ${pct(r.capture)} ${num(r.meanDelta)} [${num(r.ci95.low)},${num(r.ci95.high)}] ${r.p.toFixed(3)}  ${r.pHolm.toFixed(3)}  ${r.indexSigns.padEnd(4)} ${pct(r.trailExitShare)} ${pct(r.fallbackShare)}`);
  return [`B1 (production) capture ${pct(baselineCapture)}`, header, ...lines].join('\n');
}

/** Upper-tail standard normal quantile (Abramowitz–Stegun 26.2.23, error under 5e-4). */
function normalQuantile(tail: number): number {
  const t = Math.sqrt(-2 * Math.log(tail));
  return t - (2.515517 + 0.802853 * t + 0.010328 * t * t) / (1 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t);
}

/** Smallest mean daily ΔR this sample detects at 80% power after a Bonferroni bound on the family. */
function minimumDetectable(deltas: readonly number[], family: number): number {
  const n = Math.max(2, deltas.length);
  const mean = deltas.reduce((sum, value) => sum + value, 0) / n;
  const sd = Math.sqrt(deltas.reduce((sum, value) => sum + (value - mean) ** 2, 0) / (n - 1));
  return ((normalQuantile(0.05 / family) + normalQuantile(0.2)) * sd) / Math.sqrt(n);
}

function walkForwardReport(loaded: Loaded, baseline: readonly StudyTrade[], policies: readonly PolicyTrades[], cells: readonly string[] | undefined, options: { iterations: number; seed: number; trainMonths: number }): string {
  const result = walkForward({ dates: loaded.dates, baseline, policies, trainMonths: options.trainMonths, ...(cells === undefined ? {} : { cells }) });
  if (result.selected.length === 0) {
    return '  not enough months for a fold';
  }
  const paired = pairedBootstrap(dailyDeltas(result.dates, result.baseline, result.selected), options);
  const folds = result.folds.map((fold) => `  ${fold.test}: ${fold.selected}`).join('\n');
  const distinct = new Set(result.folds.map((fold) => fold.selected)).size;
  return `${folds}\n  out-of-sample: capture ${pct(capture(result.selected))} vs B1 ${pct(capture(result.baseline))}, meanΔR ${num(paired.meanDelta)} [${num(paired.ci95.low)},${num(paired.ci95.high)}], p ${paired.pNonPositive.toFixed(3)}, ${distinct} distinct selection(s) over ${result.folds.length} folds`;
}

async function contextCellsFor(entries: readonly StudyEntry[], dates: readonly string[]): Promise<string[]> {
  const vixPath = argument('--vix');
  const tags = vixPath === undefined ? new Map<string, Readonly<Record<string, string>>>() : vixTerciles(JSON.parse(await readFile(vixPath, 'utf8')) as Candle[], dates);
  return entries.map((entry) => `${entry.trade.context.regime}|${tags.get(entry.trade.date)?.['vix'] ?? 'vix?'}`);
}

interface CheckInput {
  readonly loaded: Loaded;
  readonly baseline: readonly StudyTrade[];
  readonly top: readonly { readonly spec: TrailSpec; readonly policy: PolicyTrades }[];
  readonly options: StudyOptions;
  readonly replay: ReplayConfig;
  readonly costs: CostModel;
  readonly stats: { iterations: number; seed: number };
}

/**
 * §5.4: entries replayed from the 1-minute dataset rebuilt as 5-minute bars, then exited on those 5-minute bars and on
 * the 1-minute bars inside them. One source, so the only difference is bar size. Δ vs B1 must keep its sign and stay
 * inside the 5-minute CI.
 */
async function fineCheck(input: CheckInput, path: string, keepMonth: (month: string) => boolean): Promise<string> {
  const fineData = parseDataset(JSON.parse(await readFile(path, 'utf8')));
  const coarseData = aggregateDataset(fineData, input.replay.barMinutes);
  const barMs = input.replay.barMinutes * 60_000;
  const sessions = new Map(fineData.sessions.map((session) => [session.date, session]));
  const picked = freezeEntries(coarseData, replayDataset(coarseData, input.replay, input.costs).trades, input.replay.warmupSessions).flatMap((entry) => {
    const session = sessions.get(entry.trade.date);
    const fine = session === undefined || !keepMonth(entry.trade.date.slice(0, 7)) ? undefined : fineBarsFor(entry, session, barMs);
    return fine === undefined ? [] : [{ entry, fine }];
  });
  const dates = coarseData.sessions.map((session) => session.date).filter((date) => keepMonth(date.slice(0, 7)));
  const run = (policy: Parameters<typeof exitPath>[1], fine: boolean): StudyTrade[] =>
    picked.map((p) => exitPath(p.entry, policy, input.options, input.replay, input.costs, fine ? p.fine : undefined));
  const [coarseB1, fineB1] = [run({ kind: 'B1' }, false), run({ kind: 'B1' }, true)];
  const lines = input.top.map(({ spec, policy }) => {
    const coarse = pairedBootstrap(dailyDeltas(dates, coarseB1, run({ kind: 'TRAIL', spec }, false)), input.stats);
    const fine = pairedBootstrap(dailyDeltas(dates, fineB1, run({ kind: 'TRAIL', spec }, true)), input.stats);
    const halfWidth = (coarse.ci95.high - coarse.ci95.low) / 2;
    const pass = Math.sign(coarse.meanDelta) === Math.sign(fine.meanDelta) && Math.abs(coarse.meanDelta - fine.meanDelta) < halfWidth;
    return `  ${policy.id.slice(0, 60).padEnd(60)} Δ5m ${num(coarse.meanDelta)} [${num(coarse.ci95.low)},${num(coarse.ci95.high)}]  Δ1m ${num(fine.meanDelta)} [${num(fine.ci95.low)},${num(fine.ci95.high)}]  ${pass ? 'PASS' : 'GRANULARITY_SENSITIVE'}`;
  });
  return [`1-minute check (${fineData.underlying}, ${picked.length} entries from the 1-minute data rebuilt as ${input.replay.barMinutes}-minute bars, ${dates.length} days):`, ...lines].join('\n');
}

/** §5.2: full replays where each exit's timing changes which later signals become trades; compared day by day. */
function coupledCheck(input: CheckInput, keepMonth: (month: string) => boolean): string {
  const replayAll = (trail: TrailSpec | undefined): ReplayTrade[] =>
    input.loaded.datasets.flatMap((dataset) =>
      replayDataset(dataset, { ...input.replay, trail, noTarget: input.options.target === 'NONE' }, input.costs).trades.filter(
        (trade) => trade.exitReason !== 'DATA_GAP' && keepMonth(trade.date.slice(0, 7)),
      ),
    );
  const base = replayAll(undefined);
  const lines = input.top.map(({ spec, policy }) => {
    const trades = replayAll(spec);
    const paired = pairedBootstrap(dayNetDeltas(input.loaded.dates, base, trades), input.stats);
    const fixedSign = Math.sign(pairedBootstrap(dailyDeltas(input.loaded.dates, input.baseline, policy.trades), input.stats).meanDelta);
    const agrees = Math.sign(paired.meanDelta) === fixedSign;
    return `  ${policy.id.slice(0, 60).padEnd(60)} ${String(trades.length).padStart(5)} trades vs ${base.length}  ΔR/day ${num(paired.meanDelta)} [${num(paired.ci95.low)},${num(paired.ci95.high)}] p ${paired.pNonPositive.toFixed(3)}  ${agrees ? 'sign agrees' : 'SIGN REVERSES'}`;
  });
  return ['coupled replay (each policy replays the whole day book):', ...lines].join('\n');
}

async function runChecks(input: CheckInput, keepMonth: (month: string) => boolean): Promise<string> {
  const finePath = argument('--fine');
  const parts = [finePath === undefined ? undefined : await fineCheck(input, finePath, keepMonth), process.argv.includes('--coupled') ? coupledCheck(input, keepMonth) : undefined];
  return parts.filter((part) => part !== undefined).join('\n\n');
}

async function main(): Promise<void> {
  const config = offlineConfig(argument('--config'));
  const base = replayConfigFrom(config).replay;
  const replay: ReplayConfig = { ...base, exits: { ...base.exits, maxHoldMinutes: numberArgument('--max-hold', base.exits.maxHoldMinutes) } };
  const fallbackCosts = defaultCostModel(config);
  const costs: CostModel = { halfSpreadPct: numberArgument('--half-spread-pct', fallbackCosts.halfSpreadPct), stopSlippagePct: numberArgument('--stop-slippage-pct', fallbackCosts.stopSlippagePct) };
  const options: StudyOptions = { target: argument('--target') === 'keep' ? 'KEEP' : 'NONE', structureExit: replay.structureExit };
  const holdoutFrom = argument('--holdout-from') ?? '2026-08';
  const holdout = process.argv.includes('--holdout');
  const stats = { iterations: numberArgument('--iterations', 2000), seed: numberArgument('--seed', 19), trainMonths: numberArgument('--train-months', 4) };
  const paths = (argument('--data') ?? '').split(',').filter(Boolean);
  if (paths.length === 0) {
    throw new Error('--data is required');
  }
  const keepMonth = (month: string): boolean => (holdout ? month >= holdoutFrom : month < holdoutFrom);
  const loaded = await loadEntries(paths, replay, costs, keepMonth);
  const baseline = loaded.entries.map((entry) => exitPath(entry, { kind: 'B1' }, options, replay, costs));
  const policies: PolicyTrades[] = STUDY_GRID.map((spec) => ({ id: specId(spec), trades: loaded.entries.map((entry) => exitPath(entry, { kind: 'TRAIL', spec }, options, replay, costs)) }));
  if (argument('--fine') !== undefined || process.argv.includes('--coupled')) {
    // Checks of already-ranked candidates: no new search, so they are logged apart and do not widen the Holm family.
    const ranked = STUDY_GRID.map((spec, i) => ({ spec, policy: policies[i] as PolicyTrades })).sort((a, b) => (capture(b.policy.trades) ?? -Infinity) - (capture(a.policy.trades) ?? -Infinity));
    const top = ranked.slice(0, numberArgument('--top', 5));
    console.log(await runChecks({ loaded, baseline, top, options, replay, costs, stats }, keepMonth));
    await appendFile(RUN_LOG, `${JSON.stringify({ kind: 'trail-check', ts: new Date().toISOString(), data: [...loaded.hashes].sort().join(','), holdout, costs, options, maxHold: replay.exits.maxHoldMinutes })}\n`);
    return;
  }
  const runs = (await priorRuns(loaded.hashes)) + 1;
  const rows = rowsFor(loaded, baseline, policies, { ...stats, runs });
  const deltas = policies.map((policy) => dailyDeltas(loaded.dates, baseline, policy.trades));
  const report = [
    `Trailing-stop study — ${holdout ? `HOLDOUT ${holdoutFrom}+` : `before ${holdoutFrom}`}, target ${options.target}, max hold ${replay.exits.maxHoldMinutes} min, half-spread ${costs.halfSpreadPct}%, stop slippage ${costs.stopSlippagePct}%`,
    `${loaded.entries.length} frozen entries over ${loaded.dates.length} days; baseline mismatches ${loaded.mismatches}; study run ${runs} on this data (Holm family ${policies.length * runs})`,
    `minimum detectable mean daily ΔR at 80% power: ${num(minimumDetectable(deltas[0] ?? [], policies.length * runs))}`,
    '',
    formatRows(rows, capture(baseline)),
    '',
    `reality check (best of ${policies.length} beats B1 after the search): p ${realityCheck(deltas, stats).toFixed(3)}`,
    '',
    'walk-forward, single policy per fold:',
    walkForwardReport(loaded, baseline, policies, undefined, stats),
    'walk-forward, regime-adaptive (regime × VIX tercile):',
    walkForwardReport(loaded, baseline, policies, await contextCellsFor(loaded.entries, loaded.dates), stats),
  ].join('\n');
  console.log(report);
  const jsonPath = argument('--json');
  if (jsonPath !== undefined) {
    await writeFile(jsonPath, JSON.stringify({ rows, mismatches: loaded.mismatches, entries: loaded.entries.length }, null, 2));
  }
  await appendFile(RUN_LOG, `${JSON.stringify({ kind: 'trail-study', ts: new Date().toISOString(), data: [...loaded.hashes].sort().join(','), holdout, costs, options, maxHold: replay.exits.maxHoldMinutes })}\n`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});

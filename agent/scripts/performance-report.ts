/**
 * Results across every journal day, overall and per setup: strategy, posture, underlying, option type, exit reason,
 * entry hour, days to expiry and day. It reads one mode and client only, so paper and live never mix.
 *
 *   npm run report:performance                                  # every day in EVENT_LOG_DIR
 *   npm run report:performance -- --from 2026-10-01 --to 2026-10-31
 *   npm run report:performance -- --json                        # the full report as JSON
 *
 * MODE (default paper) and DHAN_CLIENT_ID select the events. Net P&L is after estimated charges where the journal
 * records them; days journalled before charges were recorded show gross P&L.
 */
import 'dotenv/config';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { linesInScope, type JournalScope } from '../src/ops/journalSummary.js';
import { buildPerformanceReport, DIMENSIONS, MIN_TRADES_TO_JUDGE, type GroupStats } from '../src/ops/performanceReport.js';

const DAY_FILE = /^events-(\d{4}-\d{2}-\d{2})\.jsonl$/;

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function dayArgument(name: string): string | undefined {
  const value = argument(name);
  if (value !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${name} must be YYYY-MM-DD, got "${value}"`);
  }
  return value;
}

async function journalDays(directory: string, from: string | undefined, to: string | undefined): Promise<string[]> {
  const days = (await readdir(directory))
    .map((name) => DAY_FILE.exec(name)?.[1])
    .filter((day): day is string => day !== undefined)
    .filter((day) => (from === undefined || day >= from) && (to === undefined || day <= to));
  return days.sort();
}

function cell(value: number | undefined, width: number): string {
  return (value === undefined ? '-' : String(value)).padStart(width);
}

function row(label: string, stats: GroupStats): string {
  const flag = stats.tooFewToJudge ? '  (too few to judge)' : '';
  return [
    label.padEnd(14),
    cell(stats.trades, 7),
    cell(stats.winRatePct, 7),
    cell(stats.netPnlInr, 12),
    cell(stats.expectancyInr, 11),
    cell(stats.profitFactor, 6),
    cell(stats.avgR, 7),
    cell(stats.chargesInr, 10),
  ].join(' ') + flag;
}

const HEADER = ['group'.padEnd(14), 'trades'.padStart(7), 'win %'.padStart(7), 'net ₹'.padStart(12), 'per trade'.padStart(11), 'PF'.padStart(6), 'avg R'.padStart(7), 'charges'.padStart(10)].join(' ');

function printReport(report: ReturnType<typeof buildPerformanceReport>): void {
  const { funnel } = report;
  console.log(`\nsignal funnel: ${funnel.signals} signals → ${funnel.submitted} submitted → ${funnel.filled} filled → ${funnel.closed} closed (${funnel.rejected} rejected)`);
  const drops = Object.entries(funnel.dropped).sort(([, a], [, b]) => b - a);
  for (const [code, count] of drops) {
    console.log(`  dropped ${code}: ${count}`);
  }
  console.log(`\n${HEADER}`);
  console.log(row('ALL', report.overall));
  for (const dimension of DIMENSIONS) {
    console.log(`\nby ${dimension}`);
    for (const [key, stats] of Object.entries(report.by[dimension])) {
      console.log(row(key, stats));
    }
  }
  console.log(`\nGroups under ${MIN_TRADES_TO_JUDGE} trades are noise: do not change settings on them.`);
  if (report.closesWithoutEntry > 0) {
    console.log(`${report.closesWithoutEntry} closed trade(s) had no entry line in these days; their setup is "unknown".`);
  }
}

async function main(): Promise<void> {
  const scope: JournalScope = { mode: (process.env['MODE'] ?? 'paper').trim().toLowerCase(), clientId: process.env['DHAN_CLIENT_ID']?.trim() ?? '' };
  if (scope.clientId === '') {
    throw new Error("DHAN_CLIENT_ID is required: the report reads one client's events only");
  }
  const directory = process.env['EVENT_LOG_DIR']?.trim() || 'data/journal';
  const days = await journalDays(directory, dayArgument('--from'), dayArgument('--to'));
  if (days.length === 0) {
    throw new Error(`no journal days found in ${directory} for the range given`);
  }
  let untagged = 0;
  const lines: string[] = [];
  for (const day of days) {
    const scoped = linesInScope((await readFile(join(directory, `events-${day}.jsonl`), 'utf8')).split('\n'), scope);
    untagged += scoped.untagged;
    lines.push(...scoped.kept);
  }
  const report = buildPerformanceReport(lines);
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(`${scope.mode} / ${scope.clientId}: ${days.length} day(s), ${days[0]} to ${days[days.length - 1]}`);
    printReport(report);
  }
  if (untagged > 0) {
    console.log(`note: ${untagged} untagged line(s) predate mode and client tags and are not included`);
  }
  if (report.malformed > 0) {
    console.error(`${report.malformed} malformed line(s) were skipped; inspect the journal`);
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

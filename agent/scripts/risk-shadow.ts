/**
 * OTA-311 shadow comparison for one IST day: predicted all-in adverse loss against realised net loss, from the journal.
 *   tsx scripts/risk-shadow.ts --date 2026-11-03 [--dir data/journal]
 * It reads only. Nothing it prints changes a decision.
 */
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { journalFileName } from '../src/ops/eventLog.js';
import { joinShadow, summarizeShadow } from '../src/risk/riskShadow.js';

const argument = (name: string): string | undefined => {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
};

async function main(): Promise<void> {
  const date = argument('--date');
  if (date === undefined || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('usage: tsx scripts/risk-shadow.ts --date YYYY-MM-DD [--dir data/journal]');
  }
  const directory = argument('--dir') ?? 'data/journal';
  const text = await readFile(join(directory, journalFileName(date)), 'utf8');
  const summary = summarizeShadow(joinShadow(text.split('\n')));
  console.log(JSON.stringify({ date, ...summary }, null, 2));
  console.log(
    summary.understated === 0
      ? 'no closed trade lost more than its all-in figure'
      : `${summary.understated} closed trade(s) lost more than their all-in figure (${summary.gapThroughStops} gap-through-stop): the all-in model is not a maximum loss`,
  );
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});

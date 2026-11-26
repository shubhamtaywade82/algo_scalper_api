import { strict as assert } from 'node:assert';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { ChainRecorder } from '../src/ops/chainRecorder.js';
import { istEpoch } from './support/fixtures.js';

const SILENT = { info: () => undefined, warn: () => undefined, error: () => undefined };
const DAY = '2026-10-27';
const NIFTY = { symbol: 'NIFTY', spot: { securityId: '13', exchangeSegment: 'IDX_I' }, optionSegment: 'NSE_FNO' } as const;
const SENSEX = { symbol: 'SENSEX', spot: { securityId: '51', exchangeSegment: 'IDX_I' }, optionSegment: 'BSE_FNO' } as const;

describe('chain recorder', () => {
  it('records each underlying once per bar, mid-bar, during the session only', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chains-'));
    const calls: string[] = [];
    const recorder = new ChainRecorder({
      market: {
        listExpiries: async () => [DAY, '2026-11-03'],
        optionChain: async (spot, expiry) => {
          calls.push(`${spot.securityId}@${expiry}`);
          return { expiry, fetchedAt: 1, strikes: [] };
        },
      },
      specs: [NIFTY, SENSEX],
      directory,
      barMinutes: 5,
      minDaysToExpiry: 0,
      maxDaysToExpiry: 6,
      logger: SILENT,
    });
    for (const clock of ['10:01', '10:02', '10:04', '10:05', '10:07', '15:31']) {
      await recorder.recordIfDue(istEpoch(DAY, clock));
    }
    assert.deepEqual(calls, ['13@2026-10-27', '51@2026-10-27', '13@2026-10-27', '51@2026-10-27'], 'bars 10:00 and 10:05, two minutes in');
    const lines = (await readFile(join(directory, `chains-${DAY}.jsonl`), 'utf8')).trim().split('\n').map((line) => JSON.parse(line));
    assert.deepEqual(lines.map((line) => line.underlying), ['NIFTY', 'SENSEX', 'NIFTY', 'SENSEX']);
    await rm(directory, { recursive: true, force: true });
  });

  it('skips a failed underlying and still records the next one', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chains-'));
    const warnings: string[] = [];
    const recorder = new ChainRecorder({
      market: {
        listExpiries: async () => [DAY],
        optionChain: async (spot, expiry) => {
          if (spot.securityId === '13') {
            throw new Error('rate limited');
          }
          return { expiry, fetchedAt: 1, strikes: [] };
        },
      },
      specs: [NIFTY, SENSEX],
      directory,
      barMinutes: 5,
      minDaysToExpiry: 0,
      maxDaysToExpiry: 6,
      logger: { ...SILENT, warn: (message: string) => warnings.push(message) },
    });
    await recorder.recordIfDue(istEpoch(DAY, '10:02'));
    assert.deepEqual(warnings, ['chain snapshot failed']);
    assert.match(await readFile(join(directory, `chains-${DAY}.jsonl`), 'utf8'), /"underlying":"SENSEX"/);
    await rm(directory, { recursive: true, force: true });
  });
});

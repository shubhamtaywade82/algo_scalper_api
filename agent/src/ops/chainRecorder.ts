import { appendFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { UnderlyingSpec } from '../domain/types.js';
import { pickExpiry } from '../options/selector.js';
import type { MarketPort } from '../runtime/ports.js';
import { isMarketSessionOpen, istParts } from '../time/ist.js';
import type { Logger } from './logger.js';

/**
 * Minutes into each bar before recording. Signals fetch the chain at bar close; recording mid-bar keeps these
 * calls out of the way of entries under Dhan's one-chain-call-per-3-seconds limit.
 */
const RECORD_OFFSET_MINUTES = 2;

export interface ChainRecorderOptions {
  readonly market: Pick<MarketPort, 'listExpiries' | 'optionChain'>;
  readonly specs: readonly UnderlyingSpec[];
  readonly directory: string;
  readonly barMinutes: number;
  readonly minDaysToExpiry: number;
  readonly maxDaysToExpiry: number;
  readonly logger: Logger;
}

/**
 * Saves one option-chain snapshot per underlying per bar, so the chain gate can be replayed later; Dhan keeps no
 * chain history. Read-only, and a failed snapshot is logged and skipped, never retried into the next bar.
 */
export class ChainRecorder {
  private lastBar: number | undefined;

  constructor(private readonly options: ChainRecorderOptions) {}

  /** Records every underlying's chain when this bar has not been recorded and the offset has passed. */
  async recordIfDue(nowMs: number): Promise<void> {
    if (!isMarketSessionOpen(nowMs)) {
      return;
    }
    const minute = istParts(nowMs).minuteOfDay;
    const bar = Math.floor(minute / this.options.barMinutes);
    if (bar === this.lastBar || minute % this.options.barMinutes < RECORD_OFFSET_MINUTES) {
      return;
    }
    this.lastBar = bar;
    for (const spec of this.options.specs) {
      await this.record(spec, nowMs).catch((error: unknown) =>
        this.options.logger.warn('chain snapshot failed', { underlying: spec.symbol, error: error instanceof Error ? error.message : String(error) }),
      );
    }
  }

  private async record(spec: UnderlyingSpec, nowMs: number): Promise<void> {
    const today = istParts(nowMs).date;
    const expiry = pickExpiry(await this.options.market.listExpiries(spec.spot), today, this.options.minDaysToExpiry, this.options.maxDaysToExpiry);
    if (expiry === undefined) {
      return;
    }
    const chain = await this.options.market.optionChain(spec.spot, expiry);
    await mkdir(this.options.directory, { recursive: true });
    await appendFile(join(this.options.directory, `chains-${today}.jsonl`), `${JSON.stringify({ underlying: spec.symbol, ...chain })}\n`);
  }
}

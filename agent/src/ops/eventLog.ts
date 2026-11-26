import type { TradingMode } from '../domain/mode.js';
import { mkdir, open } from 'node:fs/promises';
import { join } from 'node:path';
import type { LedgerRecord } from '../persistence/ledger.js';
import { istParts } from '../time/ist.js';

/** File name for one IST trading day inside the journal directory. */
export function journalFileName(dayKey: string): string {
  return `events-${dayKey}.jsonl`;
}

/** The part of the ledger the event log writes to. PostgresLedger satisfies it; tests supply a fake. */
export interface LedgerWriter {
  insert(records: readonly LedgerRecord[]): Promise<number>;
}

export interface EventLogOptions {
  readonly directory: string;
  /** Identifies this process run. Every line carries it, with a per-run sequence number. */
  readonly runId: string;
  /** When set, events are also written to the ledger. Absent in journal-only mode. */
  readonly ledger?: LedgerWriter;
  readonly onError?: (error: unknown) => void;
  /** Sees every event after it is queued for the journal; operator alerts hang off this. Must not throw. */
  readonly onEvent?: (type: string, payload: Readonly<Record<string, unknown>>) => void;
  readonly now?: () => number;
  /** Events waiting for the ledger. Past this, the journal keeps them and the next start backfills. */
  readonly maxOutbox?: number;
  readonly retryBaseMs?: number;
  readonly retryMaxMs?: number;
  /** Stamped on every line, so restore can attribute each event to a mode and a client. */
  readonly scope: { readonly mode: TradingMode; readonly clientId: string };
}

const LEDGER_BATCH = 500;
const DEFAULT_MAX_OUTBOX = 10_000;
const DEFAULT_RETRY_BASE_MS = 500;
const DEFAULT_RETRY_MAX_MS = 10_000;

/**
 * Append-only JSONL audit trail, one file per IST day, with an optional ledger in PostgreSQL.
 *
 * - The journal file is the local write-ahead log. Every event is appended to it, in order, with the run
 *   id and sequence number, so the same event is never stored twice under two keys.
 * - `record` is for events whose loss is covered by backfill from the journal. It never blocks.
 * - `durable` is for events that must exist in the ledger before the next trading step. It fsyncs the
 *   journal file and awaits the ledger insert. It rejects when either fails, so the caller can refuse to act.
 * - The ledger outbox ships `record` events in batches with retries. It is bounded, so a long outage cannot
 *   grow memory without limit. Overflow is recovered from the journal at the next start.
 */
export class EventLog {
  private seq = 0;
  private chain: Promise<void> = Promise.resolve();
  private directoryReady = false;
  private readonly outbox: LedgerRecord[] = [];
  private outboxOverflow = 0;
  private durableInFlight = 0;
  /** Journal writes that failed. A retry cannot recover these, so they hold entries until the next start backfills. */
  private journalFailures = 0;
  private drain: Promise<void> | undefined;
  private retryTimer: ReturnType<typeof setTimeout> | undefined;
  private retryMs = 0;
  private readonly onError: (error: unknown) => void;
  private readonly now: () => number;
  private readonly maxOutbox: number;
  private readonly retryBaseMs: number;
  private readonly retryMaxMs: number;

  constructor(private readonly options: EventLogOptions) {
    this.onError = options.onError ?? (() => undefined);
    this.now = options.now ?? Date.now;
    this.maxOutbox = options.maxOutbox ?? DEFAULT_MAX_OUTBOX;
    this.retryBaseMs = options.retryBaseMs ?? DEFAULT_RETRY_BASE_MS;
    this.retryMaxMs = options.retryMaxMs ?? DEFAULT_RETRY_MAX_MS;
  }

  /** Fire-and-forget. A failed journal write is reported through onError, never thrown. */
  record(type: string, payload: Readonly<Record<string, unknown>>): void {
    const entry = this.next(type, payload);
    this.append(entry.file, entry.line, false).catch(() => undefined);
    this.options.onEvent?.(type, payload);
    if (this.options.ledger !== undefined) {
      this.enqueue(entry.row);
    }
  }

  /**
   * Resolves only once the event is on disk (fdatasync) and, when a ledger is configured, in the ledger.
   * Rejects otherwise, so the caller can refuse to act on an event it could not record.
   */
  async durable(type: string, payload: Readonly<Record<string, unknown>>): Promise<void> {
    const entry = this.next(type, payload);
    this.options.onEvent?.(type, payload);
    this.durableInFlight += 1;
    try {
      await this.append(entry.file, entry.line, true);
      if (this.options.ledger === undefined) {
        return;
      }
      try {
        await this.options.ledger.insert([entry.row]);
      } catch (error) {
        // The journal has the event, so it is queued for retry as well. The caller is still told it failed.
        this.enqueue(entry.row);
        throw error;
      }
    } finally {
      this.durableInFlight -= 1;
    }
  }

  /** Waits for queued journal writes and attempts one ledger drain. Best effort: it never rejects. */
  async flush(): Promise<void> {
    await this.chain;
    if (this.outbox.length > 0) {
      await this.drainOutbox();
    }
  }

  /**
   * Events that are not yet safe: queued for the ledger, dropped from a full queue, still being written
   * durably, or lost from the journal. Zero means every event so far is in the journal and the ledger.
   * The trading gate holds entries while this is non-zero.
   */
  unconfirmedEvents(): number {
    return this.outbox.length + this.outboxOverflow + this.durableInFlight + this.journalFailures;
  }

  private next(type: string, payload: Readonly<Record<string, unknown>>): {
    file: string;
    line: string;
    row: LedgerRecord;
  } {
    const at = this.now();
    this.seq += 1;
    const seq = this.seq;
    const day = istParts(at).date;
    const body = {
      ts: new Date(at).toISOString(),
      type,
      run: this.options.runId,
      seq,
      ...payload,
      mode: this.options.scope.mode,
      client: this.options.scope.clientId,
    };
    const underlying = typeof payload['underlying'] === 'string' ? payload['underlying'] : undefined;
    const correlationId = typeof payload['correlationId'] === 'string' ? payload['correlationId'] : undefined;
    return {
      file: join(this.options.directory, journalFileName(day)),
      line: `${JSON.stringify(body)}\n`,
      row: {
        sourceKey: `${this.options.runId}:${seq}`,
        runId: this.options.runId,
        seq,
        tradingDay: day,
        ts: body.ts,
        eventType: type,
        underlying,
        correlationId,
        record: body,
      },
    };
  }

  /** Appends one line after every earlier write. The returned promise rejects only when this write fails. */
  private append(file: string, line: string, durable: boolean): Promise<void> {
    const write = this.chain.then(() => this.writeLine(file, line, durable));
    this.chain = write.then(
      () => undefined,
      (error: unknown) => {
        this.journalFailures += 1;
        this.onError(error);
      },
    );
    return write;
  }

  private async writeLine(file: string, line: string, durable: boolean): Promise<void> {
    if (!this.directoryReady) {
      await mkdir(this.options.directory, { recursive: true });
      this.directoryReady = true;
    }
    const handle = await open(file, 'a');
    const before = (await handle.stat()).size;
    try {
      await handle.appendFile(line, 'utf8');
      if (durable) {
        await handle.datasync();
      }
    } catch (error) {
      // A partial write would leave a fragment in the middle of the file. Cut it back before reporting the failure.
      await handle.truncate(before).catch(() => undefined);
      throw error;
    } finally {
      await handle.close();
    }
  }

  private enqueue(row: LedgerRecord): void {
    if (this.outbox.length >= this.maxOutbox) {
      this.outboxOverflow += 1;
      if (this.outboxOverflow === 1) {
        this.onError(new Error('ledger outbox is full; events stay in the journal and are backfilled at the next start'));
      }
      return;
    }
    this.outbox.push(row);
    this.scheduleDrain(0);
  }

  private scheduleDrain(delayMs: number): void {
    if (this.retryTimer !== undefined) {
      return;
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = undefined;
      void this.drainOutbox();
    }, delayMs);
    this.retryTimer.unref?.();
  }

  private drainOutbox(): Promise<void> {
    if (this.drain !== undefined) {
      return this.drain;
    }
    const ledger = this.options.ledger;
    if (ledger === undefined) {
      return Promise.resolve();
    }
    this.drain = (async () => {
      while (this.outbox.length > 0) {
        const batch = this.outbox.slice(0, LEDGER_BATCH);
        try {
          await ledger.insert(batch);
          this.outbox.splice(0, batch.length);
          this.retryMs = 0;
        } catch (error) {
          this.retryMs = this.retryMs === 0 ? this.retryBaseMs : Math.min(this.retryMs * 2, this.retryMaxMs);
          this.onError(error);
          this.scheduleDrain(this.retryMs);
          return;
        }
      }
    })().finally(() => {
      this.drain = undefined;
    });
    return this.drain;
  }
}

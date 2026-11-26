import { z } from 'zod';
import type { RailsIntakeConfig } from '../config.js';
import type { TradingMode } from '../domain/mode.js';
import type { Logger } from '../ops/logger.js';
import type { ExternalSignalRequest, ExternalSignalResult } from './underlyingAgent.js';

/**
 * ADR-015. algo_scalper_api forwards its entry signals as `trade-intent/1` (envelope `trade-intents/1`). This intake
 * pulls them, runs each through the named agent's normal entry pipeline, and posts exactly one `intent-outcome/1`
 * per intent. It is outbound only: the agent opens no port. Rails down means no intents, so no new entries; open
 * positions are unaffected. Schemas are vendored at contracts/schemas and checked against the shared fixtures.
 */
export const tradeIntentSchema = z.object({
  schema: z.literal('trade-intent/1'),
  intent_id: z.uuid(),
  issued_at: z.iso.datetime({ offset: true }),
  expires_at: z.iso.datetime({ offset: true }),
  mode: z.enum(['paper', 'sandbox', 'live']),
  underlying: z.string().min(1),
  direction: z.enum(['BULLISH', 'BEARISH']),
  source: z.object({
    system: z.literal('algo_scalper_api'),
    strategy: z.string().min(1),
    strategy_version: z.number().int().optional(),
    signal_id: z.number().int().optional(),
  }).strict(),
  confidence: z.number().min(0).max(1),
  reasons: z.array(z.string()).optional(),
  spot_hint: z.number().optional(),
}).strict();

export const intentEnvelopeSchema = z.object({
  schema: z.literal('trade-intents/1'),
  cursor: z.string(),
  // Validated one by one, so a single malformed intent is reported instead of stalling the whole batch.
  intents: z.array(z.unknown()),
  control: z.object({
    circuit_breaker: z.object({ tripped: z.boolean() }).strict(),
    intake_enabled: z.boolean(),
    server_time: z.iso.datetime({ offset: true }),
  }).strict(),
}).strict();

type TradeIntent = z.infer<typeof tradeIntentSchema>;
type Control = z.infer<typeof intentEnvelopeSchema>['control'];

export interface IntentTarget {
  submitExternalSignal(symbol: string, request: ExternalSignalRequest): Promise<ExternalSignalResult>;
}

export interface IntentJournal {
  record(type: string, payload: Readonly<Record<string, unknown>>): void;
  durable(type: string, payload: Readonly<Record<string, unknown>>): Promise<void>;
}

export interface IntentIntakeOptions {
  readonly config: RailsIntakeConfig;
  readonly mode: TradingMode;
  readonly target: IntentTarget;
  readonly journal: IntentJournal;
  readonly logger: Logger;
  /** Intent ids already received today, replayed from the journal, so a restart never runs one twice. */
  readonly seenIntentIds: Iterable<string>;
  /**
   * False once this run has lost the trading lease. It then cannot record or trade an intent, so it must not take
   * one: polling stops and the intents stay pending in Rails for a run that holds the lease. Defaults to held.
   */
  readonly leaseHeld?: () => boolean;
  readonly fetch?: typeof fetch;
  readonly now?: () => number;
}

const REQUEST_TIMEOUT_MS = 5_000;
const OUTCOME_ATTEMPTS = 3;
const DETAIL_MAX_CHARS = 240;

function dropped(code: string, detail: string): ExternalSignalResult {
  return { outcome: 'dropped', code, detail };
}

function intentIdOf(raw: unknown): string | undefined {
  const id = (raw as { intent_id?: unknown } | null)?.intent_id;
  return typeof id === 'string' && z.uuid().safeParse(id).success ? id : undefined;
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export class IntentIntake {
  private cursor = '0';
  private readonly seen: Set<string>;
  private readonly fetch: typeof fetch;
  private readonly now: () => number;
  private lastPollError: string | undefined;

  constructor(private readonly options: IntentIntakeOptions) {
    this.seen = new Set(options.seenIntentIds);
    this.fetch = options.fetch ?? globalThis.fetch;
    this.now = options.now ?? Date.now;
  }

  /** One poll. Never throws: Rails being down only means no new intents. */
  async pollOnce(): Promise<void> {
    if (this.options.leaseHeld?.() === false) {
      this.notePollError('this run does not hold the trading lease');
      return;
    }
    let envelope: z.infer<typeof intentEnvelopeSchema>;
    try {
      envelope = intentEnvelopeSchema.parse(await this.getJson(`/api/trade_intents?after=${encodeURIComponent(this.cursor)}&mode=${this.options.mode}`));
    } catch (error) {
      this.notePollError(describe(error));
      return;
    }
    this.notePollError(undefined);
    const pause = this.pauseReason(envelope.control);
    for (const raw of envelope.intents) {
      await this.receive(raw, pause);
    }
    this.cursor = envelope.cursor;
  }

  /** Polls on an unref'd timer, one poll at a time. Returns a stop function. */
  start(): () => void {
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const loop = (): void => {
      void this.pollOnce().finally(() => {
        if (!stopped) {
          timer = setTimeout(loop, this.options.config.pollMs);
          timer.unref();
        }
      });
    };
    loop();
    return () => {
      stopped = true;
      clearTimeout(timer);
    };
  }

  private pauseReason(control: Control): ExternalSignalResult | undefined {
    if (control.circuit_breaker.tripped) {
      return dropped('CIRCUIT_BREAKER', 'the algo_scalper_api circuit breaker is tripped');
    }
    if (!control.intake_enabled) {
      return dropped('INTAKE_DISABLED', 'algo_scalper_api is not forwarding to the agent (execution.engine is not agent)');
    }
    const skewMs = Math.abs(Date.parse(control.server_time) - this.now());
    if (skewMs > this.options.config.maxClockSkewMs) {
      return dropped('CLOCK_SKEW', `Rails and agent clocks differ by ${skewMs} ms (limit ${this.options.config.maxClockSkewMs} ms)`);
    }
    return undefined;
  }

  /** Journals the receipt durably before anything else, so an intent is run at most once even across a restart. */
  private async receive(raw: unknown, pause: ExternalSignalResult | undefined): Promise<void> {
    const parsed = tradeIntentSchema.safeParse(raw);
    const intentId = parsed.success ? parsed.data.intent_id : intentIdOf(raw);
    if (intentId === undefined) {
      this.options.logger.warn('trade intent without a valid intent_id ignored');
      return;
    }
    if (this.seen.has(intentId)) {
      return;
    }
    this.seen.add(intentId);
    try {
      await this.options.journal.durable('intent_received', { intent_id: intentId, underlying: parsed.data?.underlying, direction: parsed.data?.direction });
    } catch (error) {
      void this.report(intentId, dropped('INTENT_NOT_DURABLE', describe(error)));
      return;
    }
    const refusal = !parsed.success ? dropped('SCHEMA_INVALID', z.prettifyError(parsed.error)) : this.refusal(parsed.data, pause);
    if (refusal !== undefined || !parsed.success) {
      void this.report(intentId, refusal ?? dropped('SCHEMA_INVALID', 'invalid intent'));
      return;
    }
    // Not awaited: preparing an entry can take seconds, and other underlyings' intents must not wait behind it.
    void this.run(parsed.data);
  }

  private refusal(intent: TradeIntent, pause: ExternalSignalResult | undefined): ExternalSignalResult | undefined {
    if (pause !== undefined) {
      return pause;
    }
    if (intent.mode !== this.options.mode) {
      return dropped('MODE_MISMATCH', `intent for ${intent.mode}, agent runs ${this.options.mode}`);
    }
    return undefined;
  }

  private async run(intent: TradeIntent): Promise<void> {
    let result: ExternalSignalResult;
    try {
      result = await this.options.target.submitExternalSignal(intent.underlying, {
        direction: intent.direction,
        strategy: `rails:${intent.source.strategy}`,
        reasons: intent.reasons ?? [],
        expiresAt: Date.parse(intent.expires_at),
      });
    } catch (error) {
      result = dropped('AGENT_ERROR', describe(error));
    }
    await this.report(intent.intent_id, result);
  }

  /** Posts the outcome, retrying a few times on network or server errors. A 4xx is final. */
  private async report(intentId: string, result: ExternalSignalResult): Promise<void> {
    const body = {
      schema: 'intent-outcome/1',
      intent_id: intentId,
      outcome: result.outcome,
      ...(result.code === undefined ? {} : { code: result.code }),
      ...(result.detail === undefined ? {} : { detail: result.detail.slice(0, DETAIL_MAX_CHARS) }),
      correlation_id: result.correlationId ?? `intent:${intentId}`,
      decided_at: new Date(this.now()).toISOString(),
    };
    this.options.journal.record('intent_outcome', body);
    for (let attempt = 1; attempt <= OUTCOME_ATTEMPTS; attempt += 1) {
      try {
        const response = await this.request(`/api/trade_intents/${intentId}/outcome`, { method: 'POST', body: JSON.stringify(body) });
        if (response.ok || (response.status >= 400 && response.status < 500)) {
          if (!response.ok) {
            this.options.logger.warn('intent outcome refused by Rails', { intentId, status: response.status });
          }
          return;
        }
      } catch {
        // Retried below.
      }
      await new Promise((resolve) => setTimeout(resolve, attempt * 500).unref());
    }
    this.options.logger.warn('intent outcome not delivered to Rails', { intentId, outcome: result.outcome });
  }

  private async getJson(path: string): Promise<unknown> {
    const response = await this.request(path, { method: 'GET' });
    if (!response.ok) {
      throw new Error(`Rails intent poll returned HTTP ${response.status}`);
    }
    return response.json();
  }

  /** The key is sent only in the Authorization header and is never logged. */
  private request(path: string, init: { method: 'GET' | 'POST'; body?: string }): Promise<Response> {
    return this.fetch(`${this.options.config.url}${path}`, {
      ...init,
      headers: { authorization: `Bearer ${this.options.config.key}`, 'content-type': 'application/json', accept: 'application/json' },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  }

  /** Logs only when the poll starts failing or recovers, so an outage does not flood the log. */
  private notePollError(error: string | undefined): void {
    if (error === this.lastPollError) {
      return;
    }
    if (error === undefined) {
      this.options.logger.info('Rails intent intake reachable again');
    } else {
      this.options.logger.warn('Rails intent intake unavailable; no external signals until it recovers', { error });
    }
    this.lastPollError = error;
  }
}

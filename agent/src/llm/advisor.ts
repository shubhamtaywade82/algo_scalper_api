import type { OllamaClient } from '@nemesis-oss/ollama-sdk';
import {
  OllamaBadGatewayError,
  OllamaNetworkError,
  OllamaOverloadedError,
  OllamaRateLimitError,
  OllamaServerError,
} from '@nemesis-oss/ollama-sdk';
import { z } from 'zod';
import { backoffDelayMs, cappedRetryAfterMs, delay } from './retry.js';

/**
 * The advisor is a veto, never an originator. It receives a snapshot of a
 * deterministic entry candidate and may answer SKIP; it cannot create a trade,
 * change size or levels, or override a risk violation.
 */
export const ADVISORY_SCHEMA = z.object({
  decision: z.enum(['ENTER', 'SKIP']),
  confidence: z.number().min(0).max(1),
  reason: z.string().min(1).max(240),
});

export type AdvisoryDecision = z.infer<typeof ADVISORY_SCHEMA>;

export interface AdvisoryVerdict extends AdvisoryDecision {
  /** `llm`: chat advisor; `decision`: decision-model advisor; `fail_closed`: no model answered. */
  readonly source: 'llm' | 'decision' | 'fail_closed';
}

export interface EntrySnapshot {
  readonly underlying: string;
  readonly direction: 'BULLISH' | 'BEARISH';
  readonly optionSymbol: string;
  readonly strike: number;
  readonly expiry: string;
  readonly daysToExpiry: number;
  readonly minuteOfDayIst: number;
  readonly spot: number;
  readonly entryReference: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly spreadPct: number;
  readonly openInterest: number;
  readonly lots: number;
  readonly riskInr: number;
  readonly strategy: string;
  readonly signalReasons: readonly string[];
}

export interface TradeAdvisor {
  review(snapshot: EntrySnapshot): Promise<AdvisoryVerdict>;
}

/**
 * Per-deployment knobs. Defaults preserve the original single-attempt local
 * behaviour; Ollama Cloud deployments pass retry knobs (and `keepAlive: false`)
 * from createRuntime, because cloud failures profile differently:
 *
 * - 429 / overloaded / 5xx / gateway blips are routine on a shared serverless
 *   tier and clear within a second or two, so one cheap retry beats a lost veto.
 * - keep_alive only pins a model in LOCAL VRAM; a serverless cloud ignores it,
 *   so it is not sent at all.
 * - Timeouts are NOT retried: the attempt already consumed the full budget, and
 *   this advisor sits on the live entry path where the review must stay bounded.
 */
export interface AdvisorOptions {
  /** Total attempts for transient failures (429/5xx/network); 1 disables retry. Default 1. */
  readonly maxAttempts?: number;
  /** Base delay for exponential backoff between attempts, ms. Default 250. */
  readonly backoffMs?: number;
  /** keep_alive hint sent with every request; false omits the field. Default '30m'. */
  readonly keepAlive?: string | false;
}

const DEFAULT_MAX_ATTEMPTS = 1;
const DEFAULT_BACKOFF_MS = 250;
const DEFAULT_KEEP_ALIVE = '30m';

const SYSTEM_PROMPT = [
  'You review one proposed NSE index option BUY (long premium only).',
  'Decide ENTER only if nothing in the snapshot contradicts the signal: stretched spot away from the breakout level, a wide or thin contract, or an expiry too close for the holding horizon.',
  'Otherwise answer SKIP. Never suggest a different strike, size, stop or target.',
  'Reply with JSON only: {"decision":"ENTER"|"SKIP","confidence":0..1,"reason":"<max 25 words>"}.',
].join(' ');

export function describeAdvisorError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`.slice(0, 200);
  }
  return String(error).slice(0, 200);
}

/** The slice of the Ollama SDK client this advisor depends on; injectable so tests never open a socket. */
export type AdvisorChatClient = Pick<OllamaClient, 'chatWithSchema'>;

/** Transient failures worth another attempt: 429, 503/overloaded, 5xx and proxy blips, instant network errors. */
export function isTransient(error: unknown): boolean {
  return (
    error instanceof OllamaRateLimitError ||
    error instanceof OllamaOverloadedError ||
    error instanceof OllamaServerError ||
    error instanceof OllamaBadGatewayError ||
    error instanceof OllamaNetworkError
  );
}

/** Exponential backoff with jitter; a server 429 Retry-After hint wins when present (capped). */
export function retryDelayMs(error: unknown, attempt: number, baseMs: number): number {
  if (error instanceof OllamaRateLimitError) {
    const hint = cappedRetryAfterMs(error.retryAfterMs);
    if (hint !== undefined) {
      return hint;
    }
  }
  return backoffDelayMs(attempt, baseMs);
}

export class OllamaTradeAdvisor implements TradeAdvisor {
  private readonly maxAttempts: number;
  private readonly backoffMs: number;
  private readonly keepAlive: string | false;

  constructor(
    private readonly client: AdvisorChatClient,
    private readonly model: string,
    private readonly timeoutMs: number,
    options: AdvisorOptions = {},
  ) {
    this.maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
    this.backoffMs = options.backoffMs ?? DEFAULT_BACKOFF_MS;
    this.keepAlive = options.keepAlive ?? DEFAULT_KEEP_ALIVE;
  }

  /**
   * Any failure (timeout, network, auth, malformed or schema-invalid output)
   * resolves to SKIP. An entry proceeds only on an explicit ENTER from a valid reply.
   */
  async review(snapshot: EntrySnapshot): Promise<AdvisoryVerdict> {
    for (let attempt = 1; ; attempt += 1) {
      try {
        const decision = await this.client.chatWithSchema(
          {
            model: this.model,
            messages: [
              { role: 'system', content: SYSTEM_PROMPT },
              { role: 'user', content: JSON.stringify(snapshot) },
            ],
            options: { temperature: 0 },
            // MiniCPM5 takes 0.4-0.8s without thinking trace vs 8-21s with it; past timeoutMs every reply fails closed.
            think: false,
            ...(this.keepAlive === false ? {} : { keep_alive: this.keepAlive }),
            timeoutMs: this.timeoutMs,
          },
          ADVISORY_SCHEMA,
        );
        const checked = ADVISORY_SCHEMA.safeParse(decision);
        if (!checked.success) {
          return { decision: 'SKIP', confidence: 1, reason: 'advisor reply failed schema validation', source: 'fail_closed' };
        }
        return { ...checked.data, source: 'llm' };
      } catch (error) {
        if (attempt >= this.maxAttempts || !isTransient(error)) {
          return {
            decision: 'SKIP',
            confidence: 1,
            reason: `advisor unavailable: ${describeAdvisorError(error)}`,
            source: 'fail_closed',
          };
        }
        await delay(retryDelayMs(error, attempt, this.backoffMs));
      }
    }
  }
}

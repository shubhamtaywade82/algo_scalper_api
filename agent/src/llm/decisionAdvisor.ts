import { OllamaClient } from '@nemesis-oss/ollama-sdk';
import {
  describeAdvisorError,
  isTransient,
  retryDelayMs,
  type AdvisoryVerdict,
  type AdvisorOptions,
  type EntrySnapshot,
  type TradeAdvisor,
} from './advisor.js';
import { delay } from './retry.js';

/**
 * Trade advisor backed by an Ollama decision model (System One, `POST /v1/systemone`).
 *
 * The chat advisor spends a generative model on a one-word answer and then has to
 * parse it. A decision model scores the question instead: it returns the probability
 * that the entry may proceed (`noul`) from one pass that generates no tokens, so
 * there is no JSON to validate and no thinking trace to wait for. The contract is
 * the same as the chat advisor's: veto only, and any failure resolves to SKIP.
 *
 * Transport is the SDK's `client.decision.noul()` (added in 1.26, which allows
 * System One against Ollama Cloud; the pinned 1.13 line threw "local-only" before
 * sending). The SDK validates the reply shape and maps HTTP failures onto its typed
 * errors, so this advisor only classifies and retries them. Its own retry policy
 * stays the single source of truth — shared with the chat advisor — so the client is
 * built with `retries: 0`.
 */

const DEFAULT_ENTER_THRESHOLD = 0.5;

/**
 * One typed yes/no question. `noul` is the probability that the answer is true, so the
 * verdict is the same ENTER-or-SKIP the chat advisor gives, read from one number.
 * Snapshot fields are named in backticks so the model reads them instead of guessing.
 */
export const DECISION_INSTRUCTIONS =
  'Review one proposed NSE index option BUY (long premium only), given by this state. Should the entry proceed?' +
  ' It should unless the snapshot contradicts the signal in `signalReasons`: `spot` stretched away from the breakout level,' +
  ' a wide contract (`spreadPct`), a thin contract (`openInterest`), or an expiry (`daysToExpiry`) too close for the holding horizon.';

export interface DecisionAdvisorOptions extends AdvisorOptions {
  /** Ollama host, local daemon or https://ollama.com. */
  readonly host: string;
  /** Ollama Cloud API key, sent as a bearer header and never logged. Undefined on a local daemon. */
  readonly apiKey: string | undefined;
  /** Minimum P(enter) for an ENTER verdict. Default 0.5: the verdict follows the more likely side. */
  readonly enterThreshold?: number;
  /** Injectable fetch for tests; defaults to the global one. */
  readonly fetch?: typeof fetch;
}

export class OllamaDecisionAdvisor implements TradeAdvisor {
  private readonly client: OllamaClient;
  private readonly maxAttempts: number;
  private readonly backoffMs: number;
  private readonly keepAlive: string | false;
  private readonly enterThreshold: number;

  constructor(
    private readonly model: string,
    private readonly timeoutMs: number,
    private readonly options: DecisionAdvisorOptions,
  ) {
    this.client = new OllamaClient({
      baseUrl: options.host.replace(/\/+$/, ''),
      ...(options.apiKey === undefined ? {} : { apiKey: options.apiKey }),
      timeoutMs,
      // The advisor owns the retry policy (shared with the chat advisor); the SDK must not retry underneath it.
      retries: 0,
      ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
    });
    this.maxAttempts = options.maxAttempts ?? 1;
    this.backoffMs = options.backoffMs ?? 250;
    this.keepAlive = options.keepAlive ?? '30m';
    this.enterThreshold = options.enterThreshold ?? DEFAULT_ENTER_THRESHOLD;
  }

  /** Any failure (timeout, network, auth, billing, malformed reply) resolves to SKIP, as for the chat advisor. */
  async review(snapshot: EntrySnapshot): Promise<AdvisoryVerdict> {
    for (let attempt = 1; ; attempt += 1) {
      try {
        return this.toVerdict(
          await this.client.decision.noul({
            model: this.model,
            state: { ...snapshot },
            instructions: DECISION_INSTRUCTIONS,
            minProbability: this.enterThreshold,
            // keep_alive only pins a model in local VRAM; the cloud host is serverless, so it is omitted there.
            ...(this.keepAlive === false ? {} : { keepAlive: this.keepAlive }),
          }),
        );
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

  private toVerdict(answer: { readonly noul: number; readonly bool: boolean; readonly usage: { readonly input_tokens: number } }): AdvisoryVerdict {
    const probabilityOfEnter = answer.noul;
    const usage = ` (${answer.usage.input_tokens} input tokens)`;
    if (answer.bool) {
      return {
        decision: 'ENTER',
        confidence: probabilityOfEnter,
        reason: `decision model ${this.model}: P(enter)=${probabilityOfEnter.toFixed(2)}, at or above ${this.enterThreshold}${usage}`,
        source: 'decision',
      };
    }
    return {
      decision: 'SKIP',
      // Confidence belongs to the verdict, so a SKIP carries the probability the model did not give to ENTER.
      confidence: Math.round((1 - probabilityOfEnter) * 10_000) / 10_000,
      reason: `decision model ${this.model}: P(enter)=${probabilityOfEnter.toFixed(2)}, below ${this.enterThreshold}${usage}`,
      source: 'decision',
    };
  }
}

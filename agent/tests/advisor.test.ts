import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { OllamaRateLimitError } from '@nemesis-oss/ollama-sdk';
import { OllamaTradeAdvisor, type AdvisorChatClient, type EntrySnapshot } from '../src/llm/advisor.js';

const SNAPSHOT: EntrySnapshot = {
  underlying: 'NIFTY',
  direction: 'BULLISH',
  optionSymbol: 'NIFTY 22450 CE',
  strike: 22_450,
  expiry: '2026-10-15',
  daysToExpiry: 3,
  minuteOfDayIst: 600,
  spot: 22_460,
  entryReference: 101,
  stopLossPrice: 70.7,
  targetPrice: 162.1,
  spreadPct: 0.9,
  openInterest: 500_000,
  lots: 1,
  riskInr: 2_000,
  strategy: 'range',
  signalReasons: ['ORB high broken'],
};

interface Captured {
  request: Record<string, unknown> | undefined;
}

/** Mirrors the SDK contract: chatWithSchema resolves only with a value that satisfies the schema. */
function fakeClient(behaviour: () => Promise<unknown>, captured: Captured): AdvisorChatClient {
  return {
    chatWithSchema: async (request: Record<string, unknown>, schema: { parse: (value: unknown) => unknown }) => {
      captured.request = request;
      return schema.parse(await behaviour());
    },
  } as unknown as AdvisorChatClient;
}

describe('OllamaTradeAdvisor', () => {
  it('passes an explicit ENTER through with its source marked as the LLM', async () => {
    const captured: Captured = { request: undefined };
    const advisor = new OllamaTradeAdvisor(
      fakeClient(async () => ({ decision: 'ENTER', confidence: 0.7, reason: 'clean breakout' }), captured),
      'qwen3:8b',
      8_000,
    );
    const verdict = await advisor.review(SNAPSHOT);
    assert.deepEqual(verdict, { decision: 'ENTER', confidence: 0.7, reason: 'clean breakout', source: 'llm' });
    assert.equal(captured.request?.['model'], 'qwen3:8b');
    assert.equal(captured.request?.['timeoutMs'], 8_000);
    assert.equal(captured.request?.['think'], false);
    assert.equal(captured.request?.['keep_alive'], '30m');
    assert.deepEqual(captured.request?.['options'], { temperature: 0 });
  });

  it('fails closed to SKIP when the endpoint errors, times out, or is unreachable', async () => {
    const captured: Captured = { request: undefined };
    const advisor = new OllamaTradeAdvisor(
      fakeClient(async () => {
        throw new Error('connect ECONNREFUSED');
      }, captured),
      'qwen3:8b',
      8_000,
    );
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.match(verdict.reason, /ECONNREFUSED/);
  });

  it('fails closed to SKIP when the reply does not match the schema', async () => {
    const captured: Captured = { request: undefined };
    const advisor = new OllamaTradeAdvisor(
      fakeClient(async () => ({ decision: 'MAYBE', confidence: 2, reason: '' }), captured),
      'qwen3:8b',
      8_000,
    );
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
  });

  it('treats an explicit SKIP from the model as a veto', async () => {
    const captured: Captured = { request: undefined };
    const advisor = new OllamaTradeAdvisor(
      fakeClient(async () => ({ decision: 'SKIP', confidence: 0.9, reason: 'spot stretched' }), captured),
      'qwen3:8b',
      8_000,
    );
    assert.equal((await advisor.review(SNAPSHOT)).decision, 'SKIP');
  });
});

describe('OllamaTradeAdvisor retry behaviour (Ollama Cloud deployments)', () => {
  // Instant errors only: backoff doubles per attempt; keep the base tiny so tests stay fast.
  const CLOUD_OPTS = { maxAttempts: 3, backoffMs: 1 } as const;

  function scriptedClient(behaviours: Array<() => Promise<unknown>>, captured: Captured): AdvisorChatClient {
    let call = 0;
    return {
      chatWithSchema: async (request: Record<string, unknown>, schema: { parse: (value: unknown) => unknown }) => {
        captured.request = request;
        const behaviour = behaviours[Math.min(call, behaviours.length - 1)];
        if (behaviour === undefined) {
          throw new Error(`scripted client ran out of behaviours (call ${call + 1})`);
        }
        call += 1;
        return schema.parse(await behaviour());
      },
    } as unknown as AdvisorChatClient;
  }

  function rateLimitError(retryAfterMs?: number): Error {
    // The real SDK error class: retry classification is instanceof-based, so the
    // fake must be a genuine OllamaRateLimitError (with the server's Retry-After).
    return new OllamaRateLimitError('429 too many requests', { retryAfterMs });
  }

  it('retries a transient 429 and passes the eventual ENTER through', async () => {
    const captured: Captured = { request: undefined };
    const calls: number[] = [];
    const client = scriptedClient(
      [
        async () => { calls.push(1); throw rateLimitError(); },
        async () => ({ decision: 'ENTER', confidence: 0.8, reason: 'clean breakout' }),
      ],
      captured,
    );
    const advisor = new OllamaTradeAdvisor(client, 'minimax-m2.5', 8_000, { ...CLOUD_OPTS, keepAlive: false });
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'ENTER');
    assert.equal(verdict.source, 'llm');
    assert.deepEqual(calls, [1]);
    // Cloud: keep_alive omitted entirely (serverless — nothing to keep warm).
    assert.equal(captured.request?.['keep_alive'], undefined);
    assert.equal(captured.request?.['timeoutMs'], 8_000);
  });

  it('fails closed after exhausting attempts on persistent 429s', async () => {
    const captured: Captured = { request: undefined };
    const client = scriptedClient([async () => { throw rateLimitError(); }], captured);
    const advisor = new OllamaTradeAdvisor(client, 'minimax-m2.5', 8_000, CLOUD_OPTS);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.match(verdict.reason, /OllamaRateLimitError/);
  });

  it('does NOT retry a non-transient failure (e.g. auth 401)', async () => {
    const captured: Captured = { request: undefined };
    const calls: number[] = [];
    const client = scriptedClient([async () => { calls.push(1); throw new Error('401 unauthorized'); }], captured);
    const advisor = new OllamaTradeAdvisor(client, 'minimax-m2.5', 8_000, CLOUD_OPTS);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.deepEqual(calls, [1]);
  });

  it('keeps the local default: a single attempt with keep_alive sent', async () => {
    const captured: Captured = { request: undefined };
    const calls: number[] = [];
    const client = scriptedClient([async () => { calls.push(1); throw new Error('connect ECONNREFUSED'); }], captured);
    // No options: local defaults (1 attempt, keep_alive '30m').
    const advisor = new OllamaTradeAdvisor(client, 'qwen3:8b', 8_000);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.deepEqual(calls, [1]);
    assert.equal(captured.request?.['keep_alive'], '30m');
  });
});

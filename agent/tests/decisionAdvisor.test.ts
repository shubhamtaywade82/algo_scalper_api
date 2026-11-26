import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { EntrySnapshot } from '../src/llm/advisor.js';
import { DECISION_INSTRUCTIONS, OllamaDecisionAdvisor } from '../src/llm/decisionAdvisor.js';

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

interface Sent {
  readonly url: string;
  readonly method: string | undefined;
  readonly authorization: string | undefined;
  readonly body: Record<string, unknown>;
}

type Step = { readonly status: number; readonly body?: string; readonly headers?: Record<string, string> } | { readonly error: Error };

interface Captured {
  readonly sent: Sent[];
}

/** The reply shape of /v1/systemone from Ollama's published API: answers keyed by question name, plus usage. */
function noulReply(noul: number, inputTokens = 612): Step {
  return {
    status: 200,
    body: JSON.stringify({
      model: 'clef',
      answers: { decision: { type: 'noul', noul } },
      usage: { input_tokens: inputTokens, output_tokens: 0 },
    }),
  };
}

function refused(status: number, error: string, headers?: Record<string, string>): Step {
  return { status, body: JSON.stringify({ error }), ...(headers === undefined ? {} : { headers }) };
}

/** Scripted fetch: one step per call, the last step repeats; every request is captured. */
function scriptedFetch(steps: readonly Step[], captured: Captured): typeof fetch {
  let call = 0;
  return async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    const rawBody = init?.body ?? (input instanceof Request ? await input.text() : '');
    captured.sent.push({
      url,
      method: init?.method ?? (input instanceof Request ? input.method : undefined),
      authorization: headers.get('authorization') ?? undefined,
      body: JSON.parse(String(rawBody)) as Record<string, unknown>,
    });
    const step = steps[Math.min(call, steps.length - 1)];
    if (step === undefined) {
      throw new Error(`scripted fetch ran out of steps (call ${call + 1})`);
    }
    call += 1;
    if ('error' in step) {
      throw step.error;
    }
    return new Response(step.body ?? '', { status: step.status, ...(step.headers === undefined ? {} : { headers: step.headers }) });
  };
}

// Cloud deployment: retries on, tiny backoff so the tests stay fast, keep_alive omitted.
const CLOUD = { host: 'https://ollama.com', apiKey: 'test-key', maxAttempts: 3, backoffMs: 1, keepAlive: false } as const;

/** A cloud-configured advisor whose HTTP calls are answered by `steps`; nothing leaves the process. */
function cloudAdvisor(steps: readonly Step[], captured: Captured, enterThreshold?: number): OllamaDecisionAdvisor {
  return new OllamaDecisionAdvisor('clef', 8_000, {
    ...CLOUD,
    fetch: scriptedFetch(steps, captured),
    ...(enterThreshold === undefined ? {} : { enterThreshold }),
  });
}

describe('OllamaDecisionAdvisor', () => {
  it('asks one noul question over /v1/systemone and passes a likely ENTER through with its probability', async () => {
    const captured: Captured = { sent: [] };
    const verdict = await cloudAdvisor([noulReply(0.93)], captured).review(SNAPSHOT);
    assert.equal(verdict.decision, 'ENTER');
    assert.equal(verdict.confidence, 0.93);
    assert.equal(verdict.source, 'decision');
    assert.match(verdict.reason, /decision model clef: P\(enter\)=0\.93, at or above 0\.5 \(612 input tokens\)/);
    const request = captured.sent[0];
    assert.equal(request?.url, 'https://ollama.com/v1/systemone');
    assert.equal(request?.method, 'POST');
    assert.equal(request?.authorization, 'Bearer test-key');
    assert.equal(request?.body['model'], 'clef');
    assert.deepEqual(request?.body['state'], SNAPSHOT);
    const questions = request?.body['questions'] as { decision: { type: string; instructions: string } } | undefined;
    assert.equal(questions?.decision.type, 'noul');
    assert.equal(questions?.decision.instructions, DECISION_INSTRUCTIONS);
    // Cloud: keep_alive omitted entirely (serverless — nothing to keep warm).
    assert.equal(request?.body['keep_alive'], undefined);
    assert.equal(captured.sent.length, 1);
  });

  it('vetoes with SKIP when P(enter) is below the threshold', async () => {
    const captured: Captured = { sent: [] };
    const verdict = await cloudAdvisor([noulReply(0.21)], captured).review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.confidence, 0.79, 'a SKIP carries the probability the model did not give to ENTER');
    assert.equal(verdict.source, 'decision');
    assert.match(verdict.reason, /P\(enter\)=0\.21, below 0\.5/);
  });

  it('treats exactly the threshold as ENTER and honours a custom threshold', async () => {
    const captured: Captured = { sent: [] };
    assert.equal((await cloudAdvisor([noulReply(0.5)], captured).review(SNAPSHOT)).decision, 'ENTER');
    assert.equal((await cloudAdvisor([noulReply(0.7)], captured, 0.8).review(SNAPSHOT)).decision, 'SKIP');
  });

  for (const [status, error] of [
    [401, 'Invalid API key'],
    [402, "The cloud model isn't included in the Free plan. Add usage credits or upgrade."],
    [404, 'model not found'],
  ] as const) {
    it(`fails closed at once on the server's final answer (${status})`, async () => {
      const captured: Captured = { sent: [] };
      const verdict = await cloudAdvisor([refused(status, error)], captured).review(SNAPSHOT);
      assert.equal(verdict.decision, 'SKIP');
      assert.equal(verdict.confidence, 1);
      assert.equal(verdict.source, 'fail_closed');
      assert.ok(
        verdict.reason.includes(error),
        `reason should carry the server's own explanation, got: ${verdict.reason}`,
      );
      assert.equal(captured.sent.length, 1, 'a final answer is not retried');
    });
  }

  it('retries a 429 after the requested delay and passes the eventual ENTER through', async () => {
    const captured: Captured = { sent: [] };
    const advisor = cloudAdvisor([refused(429, 'too many requests', { 'retry-after': '0.01' }), noulReply(0.88)], captured);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'ENTER');
    assert.equal(verdict.source, 'decision');
    assert.equal(captured.sent.length, 2);
  });

  it('fails closed after exhausting attempts on persistent 503s', async () => {
    const captured: Captured = { sent: [] };
    const verdict = await cloudAdvisor([refused(503, 'model loading')], captured).review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.match(verdict.reason, /model loading/);
    assert.equal(captured.sent.length, 3);
  });

  it('does not retry a timeout, because the attempt already spent the whole budget', async () => {
    const captured: Captured = { sent: [] };
    const timedOut = new DOMException('The operation was aborted due to timeout', 'TimeoutError');
    const verdict = await cloudAdvisor([{ error: timedOut }], captured).review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    // The SDK wraps an aborted fetch in OllamaGenericClientError; the wording still says the timeout.
    assert.match(verdict.reason, /aborted due to timeout/);
    assert.equal(captured.sent.length, 1);
  });

  it('retries a refused connection', async () => {
    const captured: Captured = { sent: [] };
    const advisor = cloudAdvisor([{ error: new TypeError('fetch failed') }, noulReply(0.9)], captured);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'ENTER');
    assert.equal(captured.sent.length, 2);
  });

  it('fails closed when the reply is not a noul answer', async () => {
    for (const body of [
      '{"model":"clef","answers":{"decision":{"type":"choice","choice":"ENTER"}},"usage":{"input_tokens":1,"output_tokens":0}}',
      '{"model":"clef","answers":{}}',
      '{"model":"clef","answers":{"decision":{"type":"noul","noul":1.5}}}',
      '{"model":"clef","answers":{"decision":{"type":"noul","noul":true}}}',
      'ENTER',
    ]) {
      const captured: Captured = { sent: [] };
      const verdict = await cloudAdvisor([{ status: 200, body }], captured).review(SNAPSHOT);
      assert.equal(verdict.decision, 'SKIP', body);
      assert.equal(verdict.source, 'fail_closed', body);
      assert.equal(captured.sent.length, 1, body);
    }
  });

  it('sends no bearer header and keeps the local keep_alive window on a local daemon', async () => {
    const captured: Captured = { sent: [] };
    const advisor = new OllamaDecisionAdvisor('nimble', 8_000, {
      host: 'http://127.0.0.1:11434/',
      apiKey: undefined,
      fetch: scriptedFetch([noulReply(0.9)], captured),
    });
    assert.equal((await advisor.review(SNAPSHOT)).decision, 'ENTER');
    const request = captured.sent[0];
    assert.equal(request?.url, 'http://127.0.0.1:11434/v1/systemone', 'a trailing slash on the host is not doubled');
    assert.equal(request?.authorization, undefined);
    assert.equal(request?.body['keep_alive'], '30m');
  });
});

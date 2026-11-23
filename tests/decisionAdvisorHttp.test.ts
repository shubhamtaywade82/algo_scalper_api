import { strict as assert } from 'node:assert';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import type { EntrySnapshot } from '../src/llm/advisor.js';
import { OllamaDecisionAdvisor } from '../src/llm/decisionAdvisor.js';

/**
 * Exercises the decision advisor's real HTTP path (global fetch) against a local
 * stub of Ollama's /v1/systemone endpoint. No external network is used.
 */
let server: Server;
let baseUrl = '';
let nextReply: { status: number; body: string } = { status: 200, body: '' };
let lastRequest: { path: string | undefined; authorization: string | undefined; body: string } = {
  path: undefined,
  authorization: undefined,
  body: '',
};

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

before(async () => {
  server = createServer((request, response) => {
    let body = '';
    request.on('data', (chunk: Buffer) => {
      body += chunk.toString('utf8');
    });
    request.on('end', () => {
      lastRequest = { path: request.url, authorization: request.headers.authorization, body };
      response.writeHead(nextReply.status, { 'content-type': 'application/json' });
      response.end(nextReply.body);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

function noulReply(noul: number): { status: number; body: string } {
  return {
    status: 200,
    body: JSON.stringify({
      model: 'clef',
      answers: { decision: { type: 'noul', noul } },
      usage: { input_tokens: 612, output_tokens: 0 },
    }),
  };
}

describe('OllamaDecisionAdvisor over the real HTTP path', () => {
  it('posts the question to /v1/systemone with a bearer header and accepts a likely ENTER', async () => {
    nextReply = noulReply(0.91);
    const advisor = new OllamaDecisionAdvisor('clef', 5_000, { host: baseUrl, apiKey: 'test-key', keepAlive: false });
    const verdict = await advisor.review(SNAPSHOT);
    assert.deepEqual(verdict, {
      decision: 'ENTER',
      confidence: 0.91,
      reason: 'decision model clef: P(enter)=0.91, at or above 0.5 (612 input tokens)',
      source: 'decision',
    });
    assert.equal(lastRequest.path, '/v1/systemone');
    assert.equal(lastRequest.authorization, 'Bearer test-key');
    const sent = JSON.parse(lastRequest.body) as { model: string; keep_alive?: unknown; questions: Record<string, unknown> };
    assert.equal(sent.model, 'clef');
    assert.equal(sent.keep_alive, undefined);
    assert.equal(Object.keys(sent.questions).join(), 'decision');
  });

  it('fails closed to SKIP with the server explanation when the cloud refuses the model (402)', async () => {
    nextReply = { status: 402, body: JSON.stringify({ error: "The cloud model isn't included in the Free plan. Add usage credits or upgrade." }) };
    const advisor = new OllamaDecisionAdvisor('clef', 5_000, { host: baseUrl, apiKey: 'test-key', keepAlive: false });
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.match(verdict.reason, /OllamaPaymentRequiredError: The cloud model isn't included in the Free plan/);
  });

  it('fails closed to SKIP when the server answers 500', async () => {
    nextReply = { status: 500, body: JSON.stringify({ error: 'scoring failed' }) };
    const advisor = new OllamaDecisionAdvisor('clef', 5_000, { host: baseUrl, apiKey: 'test-key', keepAlive: false });
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
    assert.match(verdict.reason, /OllamaServerError: scoring failed/);
  });
});

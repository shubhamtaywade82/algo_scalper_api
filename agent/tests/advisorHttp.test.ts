import { strict as assert } from 'node:assert';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import { OllamaClient } from '@nemesis-oss/ollama-sdk';
import { OllamaTradeAdvisor, type EntrySnapshot } from '../src/llm/advisor.js';

/**
 * Exercises the real @nemesis-oss/ollama-sdk HTTP path against a local stub of
 * Ollama's /api/chat endpoint. No external network is used.
 */
let server: Server;
let baseUrl = '';
let nextReply: { status: number; body: string } = { status: 200, body: '' };
let lastRequest: { path: string | undefined; body: string } = { path: undefined, body: '' };

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
      lastRequest = { path: request.url, body };
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

function chatReply(content: string): { status: number; body: string } {
  return {
    status: 200,
    body: JSON.stringify({
      model: 'stub',
      created_at: new Date().toISOString(),
      message: { role: 'assistant', content },
      done: true,
    }),
  };
}

describe('OllamaTradeAdvisor over the real SDK HTTP path', () => {
  it('sends a chat request to /api/chat and accepts a schema-valid ENTER', async () => {
    nextReply = chatReply('{"decision":"ENTER","confidence":0.8,"reason":"clean breakout"}');
    const client = new OllamaClient({ baseUrl });
    const advisor = new OllamaTradeAdvisor(client, 'stub-model', 5_000);
    const verdict = await advisor.review(SNAPSHOT);
    assert.deepEqual(verdict, { decision: 'ENTER', confidence: 0.8, reason: 'clean breakout', source: 'llm' });
    assert.equal(lastRequest.path, '/api/chat');
    const sent = JSON.parse(lastRequest.body) as { model: string; messages: { role: string }[] };
    assert.equal(sent.model, 'stub-model');
    assert.deepEqual(sent.messages.map((message) => message.role), ['system', 'user']);
  });

  it('fails closed to SKIP when the server returns a non-JSON reply', async () => {
    nextReply = chatReply('I think you should buy it');
    const advisor = new OllamaTradeAdvisor(new OllamaClient({ baseUrl }), 'stub-model', 5_000);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
  });

  it('fails closed to SKIP when the server errors', async () => {
    nextReply = { status: 500, body: '{"error":"model crashed"}' };
    const advisor = new OllamaTradeAdvisor(new OllamaClient({ baseUrl }), 'stub-model', 5_000);
    const verdict = await advisor.review(SNAPSHOT);
    assert.equal(verdict.decision, 'SKIP');
    assert.equal(verdict.source, 'fail_closed');
  });
});

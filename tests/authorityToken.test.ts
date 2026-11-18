import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { createAuthorityTokenProvider } from '../src/dhan/authorityToken.js';
import type { Logger } from '../src/ops/logger.js';

const URL_ = 'http://127.0.0.1:3011/api/dhan/token';
const OPERATOR_KEY = 'operator-key-value';
const CLIENT_ID = '1100000001';
const HOUR_MS = 3_600_000;

interface Call {
  readonly url: string;
  readonly headers: Record<string, string>;
}

type Reply = { readonly status: number; readonly body?: unknown } | Error;

/** A fetch that answers from a script, one reply per call, and records what it was asked. */
function scriptedFetch(replies: Reply[]): { fetch: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const fake = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    calls.push({ url: String(input), headers: { ...(init?.headers as Record<string, string> | undefined) } });
    const reply = replies.shift() ?? replies[replies.length - 1];
    if (reply === undefined) {
      throw new Error('scriptedFetch ran out of replies');
    }
    if (reply instanceof Error) {
      throw reply;
    }
    return new Response(JSON.stringify(reply.body ?? {}), { status: reply.status });
  };
  return { fetch: fake as typeof fetch, calls };
}

function tokenBody(token: string, expiresAtMs: number, clientId = CLIENT_ID): Reply {
  return { status: 200, body: { access_token: token, expires_at: new Date(expiresAtMs).toISOString(), client_id: clientId } };
}

function recordingLogger(): { logger: Logger; warnings: string[] } {
  const warnings: string[] = [];
  const logger = {
    debug: () => undefined,
    info: () => undefined,
    warn: (message: string) => warnings.push(message),
    error: () => undefined,
  } as unknown as Logger;
  return { logger, warnings };
}

function provider(replies: Reply[], options: { waitMs?: number } = {}) {
  const scripted = scriptedFetch(replies);
  const slept: number[] = [];
  const clock = { now: 0 };
  const { logger, warnings } = recordingLogger();
  const made = createAuthorityTokenProvider({
    url: URL_,
    key: OPERATOR_KEY,
    clientId: CLIENT_ID,
    fetch: scripted.fetch,
    now: () => clock.now,
    // Sleeping moves the clock, so a startup wait window can elapse without real time passing.
    sleep: async (ms) => {
      slept.push(ms);
      clock.now += ms;
    },
    logger,
    ...(options.waitMs === undefined ? {} : { startupWaitMs: options.waitMs }),
  });
  return { ...made, calls: scripted.calls, slept, warnings, clock };
}

describe('createAuthorityTokenProvider', () => {
  it('asks the authority with the operator key and reuses the token while it is comfortably valid', async () => {
    const { provide, calls } = provider([tokenBody('tok-1', 10 * HOUR_MS)]);

    assert.equal(await provide(), 'tok-1');
    assert.equal(await provide(), 'tok-1');

    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.url, URL_);
    assert.equal(calls[0]?.headers['Authorization'], `Bearer ${OPERATOR_KEY}`);
  });

  it('fetches again once the token is inside the renewal margin, so a token Rails replaced is picked up', async () => {
    const { provide, calls, clock } = provider([tokenBody('tok-1', HOUR_MS), tokenBody('tok-2', 20 * HOUR_MS)]);

    assert.equal(await provide(), 'tok-1');
    clock.now = HOUR_MS - 60_000;

    assert.equal(await provide(), 'tok-2');
    assert.equal(calls.length, 2);
  });

  it('picks up a token Rails replaced while the held one still looks valid by the clock', async () => {
    // Rails renews 30 minutes before expiry and force-refreshes on auth errors, so the expiry alone cannot be trusted.
    const { provide, clock } = provider([tokenBody('tok-1', 10 * HOUR_MS), tokenBody('tok-2', 10 * HOUR_MS)]);
    await provide();
    clock.now = 31_000;

    assert.equal(await provide(), 'tok-2');
  });

  it('does not fall back to a held token when the SDK reports a 401 and the authority cannot be reached', async () => {
    const { provide, refresh, clock } = provider([tokenBody('tok-1', 10 * HOUR_MS), new Error('connect ECONNREFUSED')]);
    await provide();
    clock.now = 1_000;

    await assert.rejects(refresh(), /unreachable/i);
  });

  it('keeps using the held token when the authority is unreachable but the token has not expired', async () => {
    const { provide, warnings, clock } = provider([tokenBody('tok-1', HOUR_MS), new Error('connect ECONNREFUSED')]);
    await provide();
    clock.now = HOUR_MS - 60_000;

    assert.equal(await provide(), 'tok-1');
    assert.equal(warnings.length, 1);
    assert.doesNotMatch(warnings.join(' '), /tok-1/);
  });

  it('throws once the held token has expired and the authority is still unreachable', async () => {
    const { provide, clock } = provider([tokenBody('tok-1', HOUR_MS), new Error('connect ECONNREFUSED')]);
    await provide();
    clock.now = HOUR_MS + 1;

    await assert.rejects(provide(), /token authority.*unreachable/i);
  });

  it('refuses a token that belongs to a different Dhan client id', async () => {
    const { provide } = provider([tokenBody('tok-other', 10 * HOUR_MS, '1199999999')]);

    await assert.rejects(provide(), (error: Error) => /client id/i.test(error.message) && !error.message.includes('tok-other'));
  });

  it('reports a rejected operator key by status, never echoing the key or a token', async () => {
    const { provide } = provider([{ status: 401, body: { error: 'unauthorized' } }]);

    await assert.rejects(provide(), (error: Error) => /401/.test(error.message) && !error.message.includes(OPERATOR_KEY));
  });

  it('does not wait out the startup window for a rejected key, since retrying cannot fix it', async () => {
    const { ensureReady, slept } = provider([{ status: 401, body: { error: 'unauthorized' } }], { waitMs: 60_000 });

    await assert.rejects(ensureReady(), (error: Error) => /operator key/i.test(error.message) && !/Start the Rails app/.test(error.message));

    assert.deepEqual(slept, []);
  });

  it('waits for the authority at startup and succeeds once it comes up', async () => {
    const { ensureReady, slept, calls } = provider(
      [new Error('connect ECONNREFUSED'), { status: 503, body: { error: 'token_unavailable' } }, tokenBody('tok-1', 10 * HOUR_MS)],
      { waitMs: 60_000 },
    );

    await ensureReady();

    assert.equal(calls.length, 3);
    assert.equal(slept.length, 2);
  });

  it('gives up at startup after the wait window and says how to run without the authority', async () => {
    const { ensureReady, slept } = provider([new Error('connect ECONNREFUSED')], { waitMs: 10_000 });

    await assert.rejects(ensureReady(), /DHAN_PIN/);

    assert.ok(slept.length >= 1);
  });
});

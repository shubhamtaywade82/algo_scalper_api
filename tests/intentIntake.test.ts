import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { IntentIntake, intentEnvelopeSchema, tradeIntentSchema } from '../src/runtime/intentIntake.js';
import type { ExternalSignalRequest, ExternalSignalResult } from '../src/runtime/underlyingAgent.js';

const NOW = Date.parse('2026-11-23T09:31:05.000+05:30');
const CONFIG = { url: 'http://127.0.0.1:3011', key: 'operator-key', pollMs: 1_000, maxClockSkewMs: 5_000 };
const SILENT = { info() {}, warn() {}, error() {} };
const FIXTURE_INTENT = JSON.parse(readFileSync('contracts/fixtures/trade-intent-1.example.json', 'utf8'));

function intent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { ...FIXTURE_INTENT, expires_at: '2026-11-23T09:31:22.114+05:30', ...overrides };
}

function envelope(intents: unknown[], control: Record<string, unknown> = {}): unknown {
  return {
    schema: 'trade-intents/1',
    cursor: '7',
    intents,
    control: { circuit_breaker: { tripped: false }, intake_enabled: true, server_time: '2026-11-23T09:31:05.200+05:30', ...control },
  };
}

interface Rig {
  readonly intake: IntentIntake;
  readonly submitted: { symbol: string; request: ExternalSignalRequest }[];
  readonly posted: Record<string, unknown>[];
  readonly durable: { type: string; payload: Record<string, unknown> }[];
  readonly urls: string[];
  readonly headers: Record<string, string>[];
}

function rig(responses: unknown[], options: { result?: ExternalSignalResult; seen?: string[]; durableFails?: boolean; leaseHeld?: () => boolean } = {}): Rig {
  const submitted: Rig['submitted'] = [];
  const posted: Rig['posted'] = [];
  const durable: Rig['durable'] = [];
  const urls: string[] = [];
  const headers: Record<string, string>[] = [];
  const fetchFake = async (url: string | URL, init?: RequestInit): Promise<Response> => {
    urls.push(String(url));
    headers.push(init?.headers as Record<string, string>);
    if (init?.method === 'POST') {
      posted.push(JSON.parse(String(init.body)));
      return new Response(JSON.stringify({ status: 'recorded' }), { status: 200 });
    }
    const body = responses.shift();
    return body instanceof Error ? Promise.reject(body) : new Response(JSON.stringify(body), { status: 200 });
  };
  const intake = new IntentIntake({
    config: CONFIG,
    mode: 'paper',
    target: {
      submitExternalSignal: async (symbol, request) => {
        submitted.push({ symbol, request });
        return options.result ?? { outcome: 'accepted', correlationId: 'E-1' };
      },
    },
    journal: {
      record: () => undefined,
      durable: async (type, payload) => {
        if (options.durableFails === true) {
          throw new Error('disk full');
        }
        durable.push({ type, payload: { ...payload } });
      },
    },
    logger: SILENT,
    seenIntentIds: options.seen ?? [],
    ...(options.leaseHeld === undefined ? {} : { leaseHeld: options.leaseHeld }),
    fetch: fetchFake as typeof fetch,
    now: () => NOW,
  });
  return { intake, submitted, posted, durable, urls, headers };
}

async function flush(): Promise<void> {
  for (let i = 0; i < 5; i += 1) {
    await new Promise<void>((resolve) => setImmediate(resolve));
  }
}

describe('Rails intent intake (ADR-015)', () => {
  it('should parse the shared contract fixtures', () => {
    assert.equal(tradeIntentSchema.safeParse(FIXTURE_INTENT).success, true);
    const env = JSON.parse(readFileSync('contracts/fixtures/trade-intents-1.example.json', 'utf8'));
    assert.equal(intentEnvelopeSchema.safeParse(env).success, true);
  });

  it('should run an intent as a rails: signal, journal it durably first and post one outcome', async () => {
    const r = rig([envelope([intent()])]);

    await r.intake.pollOnce();
    await flush();

    assert.deepEqual(r.submitted, [{
      symbol: 'NIFTY',
      request: {
        direction: 'BULLISH',
        strategy: 'rails:supertrend-adx',
        reasons: ['supertrend_bullish_adx_confirmed'],
        expiresAt: Date.parse('2026-11-23T09:31:22.114+05:30'),
      },
    }]);
    assert.equal(r.durable[0]?.type, 'intent_received');
    assert.equal(r.durable[0]?.payload['intent_id'], FIXTURE_INTENT.intent_id);
    assert.equal(r.posted.length, 1);
    assert.deepEqual(
      { ...r.posted[0], decided_at: undefined },
      { schema: 'intent-outcome/1', intent_id: FIXTURE_INTENT.intent_id, outcome: 'accepted', correlation_id: 'E-1', decided_at: undefined },
    );
    assert.equal(r.urls[0], 'http://127.0.0.1:3011/api/trade_intents?after=0&mode=paper');
    assert.equal(r.urls[1], `http://127.0.0.1:3011/api/trade_intents/${FIXTURE_INTENT.intent_id}/outcome`);
    assert.equal(r.headers[0]?.['authorization'], 'Bearer operator-key');
  });

  it('should pass the cursor back on the next poll', async () => {
    const r = rig([envelope([]), envelope([])]);

    await r.intake.pollOnce();
    await r.intake.pollOnce();

    assert.match(r.urls[1] ?? '', /after=7&mode=paper/);
  });

  it('should never run an intent twice, including ones journalled before a restart', async () => {
    const r = rig([envelope([intent()]), envelope([intent()])], { seen: [] });
    await r.intake.pollOnce();
    await r.intake.pollOnce();
    await flush();
    assert.equal(r.submitted.length, 1);

    const restarted = rig([envelope([intent()])], { seen: [FIXTURE_INTENT.intent_id] });
    await restarted.intake.pollOnce();
    await flush();
    assert.equal(restarted.submitted.length, 0);
  });

  it('should drop every intent with a reason while Rails has the circuit breaker tripped', async () => {
    const r = rig([envelope([intent()], { circuit_breaker: { tripped: true } })]);

    await r.intake.pollOnce();
    await flush();

    assert.equal(r.submitted.length, 0);
    assert.deepEqual([r.posted[0]?.['outcome'], r.posted[0]?.['code']], ['dropped', 'CIRCUIT_BREAKER']);
  });

  it('should drop intents while the clocks disagree by more than the limit', async () => {
    const r = rig([envelope([intent()], { server_time: '2026-11-23T09:32:05.000+05:30' })]);

    await r.intake.pollOnce();
    await flush();

    assert.equal(r.submitted.length, 0);
    assert.equal(r.posted[0]?.['code'], 'CLOCK_SKEW');
  });

  it('should drop an intent for another mode', async () => {
    const r = rig([envelope([intent({ mode: 'live' })])]);

    await r.intake.pollOnce();
    await flush();

    assert.equal(r.submitted.length, 0);
    assert.equal(r.posted[0]?.['code'], 'MODE_MISMATCH');
  });

  it('should report a malformed intent as SCHEMA_INVALID without running it', async () => {
    const r = rig([envelope([intent({ direction: 'SIDEWAYS' })])]);

    await r.intake.pollOnce();
    await flush();

    assert.equal(r.submitted.length, 0);
    assert.deepEqual([r.posted[0]?.['outcome'], r.posted[0]?.['code']], ['dropped', 'SCHEMA_INVALID']);
  });

  it('should not run an intent whose receipt could not be made durable', async () => {
    const r = rig([envelope([intent()])], { durableFails: true });

    await r.intake.pollOnce();
    await flush();

    assert.equal(r.submitted.length, 0);
    assert.equal(r.posted[0]?.['code'], 'INTENT_NOT_DURABLE');
  });

  it('should carry the drop code and detail of a refused entry', async () => {
    const r = rig([envelope([intent()])], { result: { outcome: 'dropped', code: 'SLOT_BUSY', detail: 'NIFTY CE side is RISK_MANAGEMENT_ACTIVE' } });

    await r.intake.pollOnce();
    await flush();

    assert.deepEqual(
      [r.posted[0]?.['outcome'], r.posted[0]?.['code'], r.posted[0]?.['detail'], r.posted[0]?.['correlation_id']],
      ['dropped', 'SLOT_BUSY', 'NIFTY CE side is RISK_MANAGEMENT_ACTIVE', `intent:${FIXTURE_INTENT.intent_id}`],
    );
  });

  it('should leave intents in Rails while this run does not hold the trading lease', async () => {
    let held = false;
    const r = rig([envelope([intent()])], { leaseHeld: () => held });

    await r.intake.pollOnce();
    assert.equal(r.urls.length, 0, 'no poll, so a run that can trade still gets the intent');

    held = true;
    await r.intake.pollOnce();
    await flush();
    assert.equal(r.submitted.length, 1);
  });

  it('should survive Rails being unreachable', async () => {
    const r = rig([new Error('ECONNREFUSED'), envelope([])]);

    await r.intake.pollOnce();
    await r.intake.pollOnce();

    assert.equal(r.submitted.length, 0);
    assert.equal(r.urls.length, 2);
  });
});

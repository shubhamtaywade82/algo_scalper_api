import { strict as assert } from 'node:assert';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { jsonlSink, recordWireCalls, redact, type WireRecord } from '../src/dhan/wireRecorder.js';

/** OTA-106 (a). The recorder writes the wire evidence the sandbox run needs, and must never change what a trading call does. */

class Orders {
  private readonly placed: unknown[] = [];
  async place(request: { quantity: number; accessToken?: string }): Promise<{ orderId: string; count: number }> {
    this.placed.push(request);
    return { orderId: `ORD-${this.placed.length}`, count: this.placed.length };
  }
  async cancel(): Promise<never> {
    throw new Error('order not cancellable');
  }
}

class Client {
  readonly orders = new Orders();
  readonly ws = { subscribed: true };
}

describe('wire recorder (OTA-106 a)', () => {
  it('redacts secret-looking keys at any depth, and keeps the trading fields', () => {
    const redacted = redact({ dhanClientId: '1100', accessToken: 'abc', nested: [{ pin: '1234', quantity: 75 }] });
    assert.deepEqual(redacted, { dhanClientId: '[redacted]', accessToken: '[redacted]', nested: [{ pin: '[redacted]', quantity: 75 }] });
  });

  it('bounds the depth of what it copies', () => {
    let deep: unknown = { leaf: 1 };
    for (let i = 0; i < 12; i += 1) {
      deep = { next: deep };
    }
    assert.match(JSON.stringify(redact(deep)), /\[truncated\]/);
  });

  it('returns exactly what the wrapped call returns, and runs the method on its own object', async () => {
    const records: WireRecord[] = [];
    const client = recordWireCalls(new Client(), ['orders'], (record) => records.push(record));
    const result = await client.orders.place({ quantity: 75 });
    assert.deepEqual(result, { orderId: 'ORD-1', count: 1 }, 'the method ran with its own state');
    assert.equal(records.length, 1);
    assert.equal(records[0]?.endpoint, 'orders.place');
    assert.equal(records[0]?.outcome.kind, 'ok');
  });

  it('records the request and response with secrets removed, and never the token', async () => {
    const records: WireRecord[] = [];
    const client = recordWireCalls(new Client(), ['orders'], (record) => records.push(record));
    await client.orders.place({ quantity: 75, accessToken: 'secret-token' });
    assert.equal(JSON.stringify(records).includes('secret-token'), false);
    assert.deepEqual(records[0]?.request, { quantity: 75, accessToken: '[redacted]' });
  });

  it('records a failed call and rethrows the same error, so the adapter still classifies it', async () => {
    const records: WireRecord[] = [];
    const client = recordWireCalls(new Client(), ['orders'], (record) => records.push(record));
    await assert.rejects(client.orders.cancel(), (error: unknown) => error instanceof Error && error.message === 'order not cancellable');
    assert.equal(records[0]?.outcome.kind, 'error');
  });

  it('keeps recording failure from changing the outcome of a trading call', async () => {
    const client = recordWireCalls(
      new Client(),
      ['orders'],
      () => {
        throw new Error('disk full');
      },
    );
    assert.deepEqual(await client.orders.place({ quantity: 1 }), { orderId: 'ORD-1', count: 1 });
  });

  it('leaves members it was not asked to wrap as they are', () => {
    const inner = new Client();
    const client = recordWireCalls(inner, ['orders'], () => undefined);
    assert.equal(client.ws, inner.ws);
  });

  it('writes one JSON line per call, in order, to a file that is created on first use', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'wire-'));
    const file = join(dir, 'nested', 'wire.jsonl');
    const client = recordWireCalls(new Client(), ['orders'], jsonlSink(file, () => undefined));
    await client.orders.place({ quantity: 1 });
    await client.orders.place({ quantity: 2 });
    await new Promise((resolve) => setTimeout(resolve, 50));
    const lines = (await readFile(file, 'utf8')).trim().split('\n').map((line) => JSON.parse(line) as WireRecord);
    assert.deepEqual(lines.map((record) => record.request), [{ quantity: 1 }, { quantity: 2 }]);
  });
});

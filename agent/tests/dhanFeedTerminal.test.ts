import { EventEmitter } from 'node:events';
import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { DhanClient } from '@nemesis-oss/dhanhq-sdk';
import { DhanFeed } from '../src/dhan/feed.js';
import type { Logger } from '../src/ops/logger.js';

interface Recorder {
  readonly logger: Logger;
  readonly errors: string[];
}

function recorder(): Recorder {
  const errors: string[] = [];
  const noop = (): void => undefined;
  return { logger: { info: noop, warn: noop, error: (message: string) => void errors.push(message) }, errors };
}

/** A market socket and an order socket that never open: the feed only needs their event surface. */
function sockets() {
  const market = Object.assign(new EventEmitter(), {
    connect: async () => undefined,
    disconnect: () => undefined,
    subscribe: () => undefined,
    unsubscribe: () => undefined,
  });
  const orders = Object.assign(new EventEmitter(), { connect: async () => undefined, disconnect: () => undefined });
  const client = { ws: Object.assign(new EventEmitter(), { market, orders, connect: async () => undefined, disconnect: () => undefined }) };
  return { client: client as unknown as Pick<DhanClient, 'ws'>, market };
}

function feed(onTerminalDisconnect?: (code: number) => void, log = recorder()) {
  const { client, market } = sockets();
  const instance = new DhanFeed(client, { istShiftedTimestamps: false, logger: log.logger, onTerminalDisconnect });
  return { instance, market, log };
}

const frame = (reasonCode: number) => ({ type: 'disconnect', reasonCode });

describe('DhanFeed terminal disconnects', () => {
  it('records a terminal server disconnect once, logs it, and reports it to the listener', async () => {
    const seen: number[] = [];
    const { instance, market, log } = feed((code) => seen.push(code));
    await instance.start();
    market.emit('disconnect', frame(806));
    market.emit('disconnect', frame(806));
    assert.equal(instance.terminalDisconnectCode(), 806);
    assert.deepEqual(seen, [806]);
    assert.equal(log.errors.length, 1);
  });

  it('treats a transient reason as recoverable: the SDK reconnects, and the feed records nothing', async () => {
    const seen: number[] = [];
    const { instance, market, log } = feed((code) => seen.push(code));
    await instance.start();
    market.emit('disconnect', frame(800));
    assert.equal(instance.terminalDisconnectCode(), undefined);
    assert.deepEqual(seen, []);
    assert.equal(log.errors.length, 0);
  });

  it('recognises every terminal reason the SDK documents, 804 to 810', async () => {
    for (let code = 804; code <= 810; code += 1) {
      const { instance, market } = feed();
      await instance.start();
      market.emit('disconnect', frame(code));
      assert.equal(instance.terminalDisconnectCode(), code, `code ${code} must end the feed`);
    }
  });

  it('ignores a disconnect frame that carries no reason', async () => {
    const { instance, market } = feed();
    await instance.start();
    market.emit('disconnect', { type: 'disconnect' });
    assert.equal(instance.terminalDisconnectCode(), undefined);
  });

  it('reports the feed as disconnected after a terminal reason, even when the socket then closes', async () => {
    const { instance, market, log } = feed();
    await instance.start();
    market.emit('disconnect', frame(806));
    market.emit('close');
    assert.equal(instance.status().status, 'disconnected');
    assert.equal(log.errors.length, 1);
  });

  it('reports disconnected when the close arrives before the terminal frame', async () => {
    const { instance, market } = feed();
    await instance.start();
    market.emit('close');
    market.emit('disconnect', frame(807));
    assert.equal(instance.status().status, 'disconnected');
    assert.equal(instance.terminalDisconnectCode(), 807);
  });

  it('keeps reconnecting after a transient reason', async () => {
    const { instance, market } = feed();
    await instance.start();
    market.emit('disconnect', frame(800));
    market.emit('close');
    assert.equal(instance.status().status, 'reconnecting');
  });
});

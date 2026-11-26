import net from 'node:net';
import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { DhanClient } from '@nemesis-oss/dhanhq-sdk';
import { DhanFeed } from '../src/dhan/feed.js';
import type { Logger } from '../src/ops/logger.js';

let resetServer: net.Server;
let refusedUrl: string;

before(async () => {
  resetServer = net.createServer((sock) => sock.resetAndDestroy());
  await new Promise<void>((resolve) => resetServer.listen(0, '127.0.0.1', resolve));
  const port = (resetServer.address() as net.AddressInfo).port;
  refusedUrl = `ws://127.0.0.1:${port}/`;
});

after(() => {
  resetServer?.close();
});

interface Line {
  readonly level: 'info' | 'warn' | 'error';
  readonly message: string;
  readonly data: Readonly<Record<string, unknown>> | undefined;
}

function recorder(): { logger: Logger; lines: Line[] } {
  const lines: Line[] = [];
  const record =
    (level: Line['level']) =>
    (message: string, data?: Readonly<Record<string, unknown>>): void => {
      lines.push({ level, message, data });
    };
  return { logger: { info: record('info'), warn: record('warn'), error: record('error') }, lines };
}

async function waitFor(condition: () => boolean, timeoutMs = 5_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!condition() && Date.now() < deadline) {
    await new Promise<void>((resolve) => setTimeout(resolve, 20));
  }
}

function refusedClient(): DhanClient {
  return new DhanClient({ clientId: '1', token: 'token', marketFeedUrl: refusedUrl, orderUpdateUrl: refusedUrl });
}

describe('DhanFeed socket errors', () => {
  it('keeps the process running when both sockets are refused, and logs each failure with its code only', async () => {
    const { logger, lines } = recorder();
    const dhan = refusedClient();
    const feed = new DhanFeed(dhan, { istShiftedTimestamps: false, logger, connectOrderUpdates: true });
    try {
      await feed.start();
      await waitFor(() => lines.filter((line) => line.level === 'error').length >= 2);
      const market = lines.find((line) => line.message.includes('market feed'));
      const orders = lines.find((line) => line.message.includes('order update'));
      assert.ok(['ECONNREFUSED', 'ECONNRESET'].includes(String(market?.data?.['code'])));
      assert.ok(['ECONNREFUSED', 'ECONNRESET'].includes(String(orders?.data?.['code'])));
      assert.ok(!JSON.stringify(lines).includes('token'), 'the access token never reaches a log line');
    } finally {
      dhan.ws.disconnect();
    }
  });

  it('connects only the market socket when order updates are not wanted, so no order-update connection is attempted', async () => {
    const { logger, lines } = recorder();
    const dhan = refusedClient();
    const feed = new DhanFeed(dhan, { istShiftedTimestamps: false, logger, connectOrderUpdates: false });
    try {
      await feed.start();
      await waitFor(() => lines.some((line) => line.message.includes('market feed')));
      assert.ok(lines.some((line) => line.message.includes('market feed')), 'the market socket failure is logged');
      assert.equal(lines.some((line) => line.message.includes('order update')), false, 'no order-update connection was attempted');
    } finally {
      dhan.ws.disconnect();
    }
  });
});

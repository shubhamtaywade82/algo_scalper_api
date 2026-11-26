import { strict as assert } from 'node:assert';
import { EventEmitter } from 'node:events';
import { after, describe, it } from 'node:test';
import { createElement } from 'react';
import { render, type Instance } from 'ink';
import type { Runtime } from '../src/runtime/createRuntime.js';
import App, { isConfirmation } from '../src/ui/App.js';
import { COCKPIT_KEYS } from '../src/ui/keymap.js';
import { feedStatusText } from '../src/ui/cockpit.js';
import { fakeRuntime } from './support/fakeRuntime.js';

const plain = (text: string) => text.replace(/\x1b\[[0-9;]*m/g, '');
const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

class FakeStdout extends EventEmitter {
  columns = 170;
  rows = 48;
  isTTY = false;
  readonly chunks: string[] = [];
  write(chunk: string | Uint8Array): boolean {
    this.chunks.push(String(chunk));
    return true;
  }
  get text(): string {
    return plain(this.chunks.join(''));
  }
}

/** Follows Ink 5's contract: keypresses are queued and announced with 'readable', then drained with read(). */
class FakeStdin extends EventEmitter {
  isTTY = true;
  private readonly queue: string[] = [];
  read(): string | null {
    return this.queue.shift() ?? null;
  }
  setRawMode(_enabled: boolean): this {
    return this;
  }
  setEncoding(_encoding: string): this {
    return this;
  }
  resume(): this {
    return this;
  }
  pause(): this {
    return this;
  }
  ref(): this {
    return this;
  }
  unref(): this {
    return this;
  }
  press(text: string): void {
    this.queue.push(text);
    this.emit('readable');
  }
}

/**
 * Renders the app into a fake terminal, runs the steps, and always unmounts: a failed assertion
 * must not leave the app's refresh timer running, or the test process never exits.
 */
async function withTerminal(
  runtime: Runtime,
  options: { columns?: number; rows?: number },
  steps: (terminal: { stdout: FakeStdout; press: (text: string) => void }) => Promise<void>,
): Promise<void> {
  const stdout = new FakeStdout();
  stdout.columns = options.columns ?? 170;
  stdout.rows = options.rows ?? 48;
  const stdin = new FakeStdin();
  const instance: Instance = render(createElement(App, { runtime }), {
    stdout: stdout as unknown as NodeJS.WriteStream,
    stdin: stdin as unknown as NodeJS.ReadStream,
    debug: true,
    exitOnCtrlC: false,
    patchConsole: false,
  });
  try {
    await wait(80);
    await steps({ stdout, press: (text) => stdin.press(text) });
  } finally {
    instance.unmount();
  }
}

describe('operator cockpit (Ink app, fake terminal)', () => {
  const stops: Array<() => Promise<void>> = [];
  after(async () => {
    for (const stop of stops) {
      await stop();
    }
  });

  it('draws the cockpit and needs two presses before changing the entry block', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      assert.match(stdout.text, /NSE INDEX OPTIONS/);
      assert.match(stdout.text, /UNDERLYINGS \(1\)/);
      assert.match(stdout.text, /entries OPEN/);

      press('k');
      await wait(40);
      assert.match(stdout.text, /press k again within 5s to toggle the entry block/);
      assert.equal(runtime.orchestrator.snapshot().day.killSwitchReason, undefined, 'one press must not change anything');

      press('k');
      await wait(40);
      assert.match(stdout.text, /new entries blocked; press k again to clear/);
      assert.match(stdout.text, /entries BLOCKED/);
    });
  });

  it('moves the selection with the arrow keys without asking for a second press', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      press('\u001B[B');
      await wait(40);
      assert.doesNotMatch(stdout.text, /again within 5s/);
    });
  });

  it('needs a second ctrl+c to stop, and then stops gracefully like s', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      press('\u0003');
      await wait(40);
      assert.match(stdout.text, /press s or Ctrl\+C again within 5s to stop/);
      assert.equal(runtime.orchestrator.snapshot().phase, 'RUNNING', 'a single press must not stop the agent');

      press('\u0003');
      await wait(80);
      assert.match(stdout.text, /stopping: flattening open positions before exit/);
      assert.equal(runtime.orchestrator.snapshot().phase, 'STOPPED');
    });
  });

  it('needs a second press before it cycles the posture or toggles a strategy family', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      assert.match(stdout.text, /ALIGNED/);

      press('p');
      await wait(40);
      assert.match(stdout.text, /press p again within 5s to cycle the strategy posture/);
      assert.equal(runtime.orchestrator.snapshot().strategy?.posture, 'aligned', 'one press must not change the posture');
      press('p');
      await wait(40);
      assert.equal(runtime.orchestrator.snapshot().strategy?.posture, 'confirmed');

      press('1');
      await wait(40);
      assert.match(stdout.text, /press 1 again within 5s to toggle Range break/);
      assert.equal(runtime.orchestrator.snapshot().strategy?.strategies.find((s) => s.id === 'range')?.on, true, 'one press must not toggle the family');
      press('1');
      await wait(40);
      assert.match(stdout.text, /Range break off/i);
      assert.equal(runtime.orchestrator.snapshot().strategy?.strategies.find((s) => s.id === 'range')?.on, false);
    });
  });

  it('starts a test trade only on the second t press', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      press('t');
      await wait(40);
      assert.match(stdout.text, /press t again within 5s to start a test trade on NIFTY/);
      assert.doesNotMatch(stdout.text, /no spot tick received yet/);

      press('t');
      await wait(40);
      assert.match(stdout.text, /no spot tick received yet/i);
    });
  });

  it('prints the key line from the same table the README and the footer are built from', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, {}, async ({ stdout, press }) => {
      press('?');
      await wait(40);
      assert.ok(stdout.text.includes(COCKPIT_KEYS.map((key) => key.help).join(' · ')), 'the key line lists every key');
    });
  });

  it('shows a resize notice instead of a broken frame on a small terminal', async () => {
    const { runtime, stop } = fakeRuntime();
    stops.push(stop);
    await withTerminal(runtime, { columns: 100, rows: 30 }, async ({ stdout }) => {
      assert.match(stdout.text, /Terminal too small for the operator cockpit/);
      assert.doesNotMatch(stdout.text, /NSE INDEX OPTIONS/);
    });
  });
});

describe('isConfirmation', () => {
  const open = { action: 'stop' as const, symbol: undefined, expiresAt: 10_000 };

  it('confirms the same action on the same target inside the window', () => {
    assert.equal(isConfirmation(open, 'stop', undefined, 9_999), true);
  });

  it('does not confirm once the window has closed, even if the render still shows it armed', () => {
    assert.equal(isConfirmation(open, 'stop', undefined, 10_000), false);
    assert.equal(isConfirmation(open, 'stop', undefined, 10_400), false);
  });

  it('does not confirm a different action or a different underlying', () => {
    const close = { action: 'close' as const, symbol: 'NIFTY', expiresAt: 10_000 };
    assert.equal(isConfirmation(close, 'close', 'SENSEX', 9_000), false);
    assert.equal(isConfirmation(close, 'block', undefined, 9_000), false);
    assert.equal(isConfirmation(undefined, 'stop', undefined, 9_000), false);
  });
});

describe('feedStatusText', () => {
  it('returns LIVE for low latency ticks within stale threshold', () => {
    assert.match(plain(feedStatusText(50, 5000)), /● LIVE/);
  });

  it('returns DELAYED when latency exceeds half the stale threshold', () => {
    assert.match(plain(feedStatusText(3000, 5000)), /◐ DELAYED/);
  });

  it('returns STALE when latency exceeds the stale threshold', () => {
    assert.match(plain(feedStatusText(6000, 5000)), /✖ STALE/);
  });

  it('returns NO TICK when tick latency is undefined', () => {
    assert.match(plain(feedStatusText(undefined, 5000)), /○ NO TICK/);
  });

  it('returns CLOSED when marketOpen is false regardless of tick latency', () => {
    assert.match(plain(feedStatusText(50, 5000, false)), /■ CLOSED/);
  });

  it('returns WS DOWN when feed status is disconnected', () => {
    assert.match(plain(feedStatusText(undefined, 5000, true, 'disconnected')), /✖ WS DOWN/);
  });

  it('returns RECONNECTING when feed status is reconnecting', () => {
    assert.match(plain(feedStatusText(undefined, 5000, true, 'reconnecting')), /◐ RECONNECTING/);
  });

  it('returns CONNECTING when feed status is connecting', () => {
    assert.match(plain(feedStatusText(undefined, 5000, true, 'connecting')), /◐ CONNECTING/);
  });
});

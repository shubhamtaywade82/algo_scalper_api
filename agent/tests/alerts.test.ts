import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import {
  alertText,
  buildAlertListener,
  createAlertSink,
  createTelegramAlertSink,
  formatTelegramAlert,
} from '../src/ops/alerts.js';

const SILENT = { info: () => undefined, warn: () => undefined, error: () => undefined };

describe('operator alerts', () => {
  it('posts alert-worthy events as one plain-text line and ignores routine ones', async () => {
    const posted: Array<[string, string]> = [];
    const sink = createAlertSink('https://ntfy.sh/topic', SILENT, async (url, body) => {
      posted.push([url, body]);
      return { ok: true, status: 200 };
    });
    sink('signal_detected', { underlying: 'NIFTY' });
    sink('daily_loss_breach', { dayPnlInr: -40391.4, limitInr: 37692.13, nested: { skip: true } });
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(posted, [['https://ntfy.sh/topic', 'daily_loss_breach dayPnlInr=-40391.4 limitInr=37692.13']]);
  });

  it('logs a failed delivery instead of throwing into the trading path', async () => {
    const warnings: string[] = [];
    const logger = { ...SILENT, warn: (message: string) => warnings.push(message) };
    const sink = createAlertSink('https://ntfy.sh/topic', logger, async () => {
      throw new Error('network down');
    });
    assert.doesNotThrow(() => sink('halted', { underlying: 'SENSEX' }));
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(warnings, ['alert delivery failed']);
  });

  it('formats only scalar payload fields', () => {
    assert.equal(alertText('exit_rejected', { underlying: 'NIFTY', code: 'DH-906', detail: { a: 1 } }), 'exit_rejected underlying=NIFTY code=DH-906');
  });
});

describe('telegram operator alerts', () => {
  it('formats alert with emoji, uppercase bold type, and monospace parameter lines', () => {
    const alert = formatTelegramAlert('daily_loss_breach', {
      dayPnlInr: -40391.4,
      limitInr: 37692.13,
      ignoredObject: { a: 1 },
    });
    assert.equal(alert.text, '🛑 DAILY_LOSS_BREACH\ndayPnlInr: -40391.4\nlimitInr: 37692.13');
    assert.equal(alert.entities[0]?.type, 'bold');
    assert.equal(alert.entities[1]?.type, 'code');
    assert.equal(alert.entities[2]?.type, 'code');
    assert.match(alert.toHTML(), /🛑 <b>DAILY_LOSS_BREACH<\/b>/);
  });

  it('delivers formatted alert to Telegram Bot API with native entities', async () => {
    const posted: Array<[string, unknown]> = [];
    const sink = createTelegramAlertSink({ botToken: 'mock-bot-token', chatId: '-100987654' }, SILENT, async (url, body) => {
      posted.push([url, body]);
      return { ok: true, status: 200 };
    });

    sink('signal_detected', { underlying: 'NIFTY' });
    sink('halted', { reason: 'MANUAL_HALT', underlying: 'BANKNIFTY' });
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(posted.length, 1);
    const [url, body] = posted[0]!;
    assert.equal(url, 'https://api.telegram.org/botmock-bot-token/sendMessage');
    const payload = body as { chat_id: string; text: string; entities: Array<{ type: string }> };
    assert.equal(payload.chat_id, '-100987654');
    assert.match(payload.text, /^⚠️ HALTED/);
    assert.ok(payload.entities.length >= 2);
  });

  it('logs a warning when Telegram rejects the request', async () => {
    const warnings: Array<{ message: string; meta?: unknown }> = [];
    const logger = { ...SILENT, warn: (message: string, meta?: unknown) => warnings.push({ message, meta }) };
    const sink = createTelegramAlertSink({ botToken: 'bad-token', chatId: '123' }, logger, async () => ({
      ok: false,
      status: 401,
    }));

    sink('halted', { reason: 'CIRCUIT' });
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(warnings.length, 1);
    assert.equal(warnings[0]?.message, 'telegram alert delivery refused');
  });

  it('catches network errors without throwing', async () => {
    const warnings: Array<{ message: string; meta?: unknown }> = [];
    const logger = { ...SILENT, warn: (message: string, meta?: unknown) => warnings.push({ message, meta }) };
    const sink = createTelegramAlertSink({ botToken: 'tok', chatId: '123' }, logger, async () => {
      throw new Error('connect ECONNREFUSED');
    });

    assert.doesNotThrow(() => sink('halted', { reason: 'CIRCUIT' }));
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(warnings.length, 1);
    assert.equal(warnings[0]?.message, 'telegram alert delivery failed');
  });
});

describe('buildAlertListener', () => {
  it('returns undefined when no sinks are configured', () => {
    assert.equal(buildAlertListener({}, SILENT), undefined);
  });

  it('dispatches to both webhook and telegram when both are configured', async () => {
    const webhookDeliveries: string[] = [];
    const telegramDeliveries: Array<{ url: string; body: unknown }> = [];

    const listener = buildAlertListener(
      {
        alertWebhookUrl: 'https://ntfy.sh/my-topic',
        telegram: { botToken: 'mock-bot', chatId: 'mock-chat' },
      },
      SILENT,
      {
        postText: async (url, body) => {
          webhookDeliveries.push(body);
          return { ok: true, status: 200 };
        },
        postJson: async (url, body) => {
          telegramDeliveries.push({ url, body });
          return { ok: true, status: 200 };
        },
      },
    );

    assert.ok(listener !== undefined);

    listener('halted', { reason: 'VOLATILITY' });
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(webhookDeliveries.length, 1);
    assert.equal(telegramDeliveries.length, 1);
    assert.match(webhookDeliveries[0]!, /halted reason=VOLATILITY/);
    const tg = telegramDeliveries[0]!.body as { chat_id: string; text: string };
    assert.equal(tg.chat_id, 'mock-chat');
    assert.match(tg.text, /^⚠️ HALTED/);
  });
});

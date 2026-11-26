import { bold, code, fmt, join, toTelegramPayload, type FormattedMessage } from '@nemesis-oss/tg-format';
import type { Logger } from './logger.js';

/** Journal events an operator must hear about without watching the cockpit. */
export const ALERT_EVENT_TYPES: ReadonlySet<string> = new Set([
  'daily_loss_breach',
  'book_kill_switch',
  'broker_kill_switch_failed',
  'halted',
  'feed_terminal',
  'entry_rejected',
  'exit_rejected',
  'late_entry_fill',
  'audit_gap',
  'position_stale',
  'position_client_side',
]);

const ALERT_TIMEOUT_MS = 5_000;

export type AlertListener = (type: string, payload: Readonly<Record<string, unknown>>) => void;

export type PostText = (url: string, body: string) => Promise<{ ok: boolean; status: number }>;
export type PostJson = (url: string, body: unknown) => Promise<{ ok: boolean; status: number }>;

const postText: PostText = (url, body) =>
  fetch(url, { method: 'POST', body, signal: AbortSignal.timeout(ALERT_TIMEOUT_MS) });

const postJson: PostJson = (url, body) =>
  fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(ALERT_TIMEOUT_MS),
  });

/** One line a phone notification can show: event type, then the payload's scalar fields. */
export function alertText(type: string, payload: Readonly<Record<string, unknown>>): string {
  const fields = Object.entries(payload)
    .filter(([, value]) => ['string', 'number', 'boolean'].includes(typeof value))
    .map(([key, value]) => `${key}=${String(value)}`);
  return [type, ...fields].join(' ');
}

/** Visual markers for critical trading events in chat clients. */
const ALERT_ICONS: Readonly<Record<string, string>> = {
  daily_loss_breach: '🛑',
  book_kill_switch: '⛔',
  broker_kill_switch_failed: '🚨',
  halted: '⚠️',
  entry_rejected: '❌',
  exit_rejected: '❌',
  late_entry_fill: '⏱️',
  audit_gap: '🔍',
};

/** Formats an alert with native bold header, event icon, and monospace parameters. */
export function formatTelegramAlert(type: string, payload: Readonly<Record<string, unknown>>): FormattedMessage {
  const icon = ALERT_ICONS[type] ?? '🔔';
  const header = fmt`${icon} ${bold(type.toUpperCase())}`;
  const fields = Object.entries(payload)
    .filter(([, value]) => ['string', 'number', 'boolean'].includes(typeof value))
    .map(([key, value]) => code(`${key}: ${String(value)}`));
  return fields.length === 0 ? header : fmt`${header}\n${join(fields, '\n')}`;
}

/**
 * Returns an event listener that POSTs alert-worthy events as plain text (the format ntfy.sh accepts).
 * Delivery is best effort: a failure is logged and never reaches the trading path.
 */
export function createAlertSink(url: string, logger: Logger, post: PostText = postText): AlertListener {
  return (type, payload) => {
    if (!ALERT_EVENT_TYPES.has(type)) {
      return;
    }
    post(url, alertText(type, payload))
      .then((response) => {
        if (!response.ok) {
          logger.warn('alert delivery refused', { type, status: response.status });
        }
      })
      .catch((error: unknown) => logger.warn('alert delivery failed', { type, error: error instanceof Error ? error.message : String(error) }));
  };
}

export interface TelegramAlertConfig {
  readonly botToken: string;
  readonly chatId: string;
}

/**
 * Returns an event listener that sends alert-worthy events to Telegram Bot API with native entities.
 * Delivery is best effort: a failure is logged and never reaches the trading path.
 */
export function createTelegramAlertSink(config: TelegramAlertConfig, logger: Logger, post: PostJson = postJson): AlertListener {
  const url = `https://api.telegram.org/bot${config.botToken}/sendMessage`;
  return (type, payload) => {
    if (!ALERT_EVENT_TYPES.has(type)) {
      return;
    }
    const message = formatTelegramAlert(type, payload);
    const body = {
      chat_id: config.chatId,
      ...toTelegramPayload(message, 'entities'),
    };
    post(url, body)
      .then((response) => {
        if (!response.ok) {
          logger.warn('telegram alert delivery refused', { type, status: response.status });
        }
      })
      .catch((error: unknown) => logger.warn('telegram alert delivery failed', { type, error: error instanceof Error ? error.message : String(error) }));
  };
}

export interface OpsAlertConfig {
  readonly alertWebhookUrl?: string | undefined;
  readonly telegram?: TelegramAlertConfig | undefined;
}

export interface AlertTransports {
  readonly postText?: PostText | undefined;
  readonly postJson?: PostJson | undefined;
}

/** Combines all configured alert sinks into one listener, or returns undefined if none configured. */
export function buildAlertListener(
  ops: OpsAlertConfig,
  logger: Logger,
  transports: AlertTransports = {},
): AlertListener | undefined {
  const sinks: AlertListener[] = [];
  if (ops.alertWebhookUrl !== undefined) {
    sinks.push(createAlertSink(ops.alertWebhookUrl, logger, transports.postText));
  }
  if (ops.telegram !== undefined) {
    sinks.push(createTelegramAlertSink(ops.telegram, logger, transports.postJson));
  }
  if (sinks.length === 0) {
    return undefined;
  }
  return (type, payload) => {
    for (const sink of sinks) {
      sink(type, payload);
    }
  };
}

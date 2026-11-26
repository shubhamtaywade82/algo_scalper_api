import { appendFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

/**
 * Wire evidence for the sandbox run (OTA-106). Every call to a named client namespace is recorded as one JSON line: the
 * request, the response or the error, and the time. Values that look like credentials or identity are replaced before
 * they are written, so a recording can be checked into the repository.
 *
 * The recorder never changes a call. The method runs on its own object, its response is returned as is, and its error
 * is rethrown as is. A failure to record is reported and ignored, because it must not change a trade.
 */

export type WireOutcome = { readonly kind: 'ok'; readonly response: unknown } | { readonly kind: 'error'; readonly error: string };

export interface WireRecord {
  readonly ts: string;
  readonly endpoint: string;
  readonly request: unknown;
  readonly outcome: WireOutcome;
}

export type WireSink = (record: WireRecord) => void;

/** Keys whose values are never written. Matched case-insensitively anywhere in the object. */
const SECRET_KEY = /token|secret|pin|totp|passw|authoriz|cookie|client.?id|mobile|email/i;
const MAX_DEPTH = 8;
const REDACTED = '[redacted]';

/** A copy of `value` that is safe to write: secret-looking keys are replaced, and the copy stops at a fixed depth. */
export function redact(value: unknown, depth = 0): unknown {
  if (depth > MAX_DEPTH) {
    return '[truncated]';
  }
  if (Array.isArray(value)) {
    return value.map((item) => redact(item, depth + 1));
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, SECRET_KEY.test(key) ? REDACTED : redact(item, depth + 1)]),
    );
  }
  return value;
}

function describeError(error: unknown): string {
  return (error instanceof Error ? `${error.name}: ${error.message}` : String(error)).slice(0, 240);
}

function emit(sink: WireSink, record: WireRecord): void {
  try {
    sink(record);
  } catch {
    // Recording is evidence, not control. A failed write must not change the trading outcome.
  }
}

function wrapNamespace(namespace: object, name: string, sink: WireSink, clock: () => number): object {
  return new Proxy(namespace, {
    get(target, prop) {
      const value: unknown = Reflect.get(target, prop, target);
      if (typeof value !== 'function' || typeof prop !== 'string') {
        return value;
      }
      const endpoint = `${name}.${prop}`;
      return async (...args: unknown[]): Promise<unknown> => {
        const ts = new Date(clock()).toISOString();
        const request = redact(args[0]);
        let response: unknown;
        try {
          response = await Reflect.apply(value, target, args);
        } catch (error) {
          emit(sink, { ts, endpoint, request, outcome: { kind: 'error', error: describeError(error) } });
          throw error;
        }
        emit(sink, { ts, endpoint, request, outcome: { kind: 'ok', response: redact(response) } });
        return response;
      };
    },
  });
}

/**
 * The client with each named namespace wrapped, so every method call on it is recorded. Other members are returned unchanged.
 */
export function recordWireCalls<C extends object>(
  client: C,
  namespaces: readonly (keyof C & string)[],
  sink: WireSink,
  clock: () => number = Date.now,
): C {
  return new Proxy(client, {
    get(target, prop, receiver) {
      const value: unknown = Reflect.get(target, prop, receiver);
      if (typeof prop === 'string' && (namespaces as readonly string[]).includes(prop) && value !== null && typeof value === 'object') {
        return wrapNamespace(value, prop, sink, clock);
      }
      return value;
    },
  });
}

/**
 * A sink that appends each record as one JSON line, in the order the calls were made. The file and its directory are
 * created on first write. Write failures go to `onError`, and never reach the caller.
 */
export function jsonlSink(file: string, onError: (error: unknown) => void): WireSink {
  let queue: Promise<void> = Promise.resolve();
  let directoryReady: Promise<unknown> | undefined;
  return (record) => {
    directoryReady ??= mkdir(dirname(file), { recursive: true });
    const ready = directoryReady;
    queue = queue
      .then(() => ready)
      .then(() => appendFile(file, `${JSON.stringify(record)}\n`))
      .catch(onError);
  };
}

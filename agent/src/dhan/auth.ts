import { AuthenticationError, DhanAuth } from '@nemesis-oss/dhanhq-sdk';

const DHAN_AUTH_BASE = 'https://auth.dhan.co';
const BROKER_ERROR_KEYS = ['errorMessage', 'message', 'error', 'errorType'] as const;

/**
 * A TOTP code generated with fewer seconds left in its window can reach the broker
 * after the window has rolled over and be rejected as expired. Below this margin the
 * provider waits for the next window instead of sending a code that may already be stale.
 */
export const TOTP_MIN_VALID_SECONDS = 5;

export interface TotpProviderOptions {
  readonly now?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Supplies a fresh 6-digit TOTP code for each login. The secret is held only inside this
 * closure and never leaves it. Injected clock and sleep make the window logic testable.
 */
export function createTotpProvider(secret: string, options: TotpProviderOptions = {}): () => Promise<string> {
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? defaultSleep;
  return async () => {
    const remaining = DhanAuth.totpSecondsRemaining({ timestamp: now() });
    if (remaining < TOTP_MIN_VALID_SECONDS) {
      // The +1 second guarantees the wait lands inside the next window.
      await sleep((remaining + 1) * 1000);
    }
    return DhanAuth.generateTotp(secret, { timestamp: now() });
  };
}

/**
 * The SDK treats a token without a usable expiry as always due for renewal, so every API
 * call would start a fresh PIN+TOTP login, and each login can invalidate the previous token.
 * Startup therefore refuses such a token rather than running on it.
 */
export function assertUsableToken(token: { readonly expiresAt?: number } | undefined, now: number): void {
  if (token === undefined) {
    throw new Error('Dhan login returned no token');
  }
  if (token.expiresAt === undefined || !Number.isFinite(token.expiresAt)) {
    throw new Error(
      'Dhan login returned a token without an expiry; refusing to run because every request would trigger a fresh PIN+TOTP login',
    );
  }
  if (now >= token.expiresAt) {
    throw new Error(
      `Dhan login returned a token that is already expired (${new Date(token.expiresAt).toISOString()}); check the host clock`,
    );
  }
}

/** Human-readable expiry for logs. Never throws, even on a malformed timestamp. */
export function formatExpiry(expiresAt: number | undefined): string {
  return expiresAt !== undefined && Number.isFinite(expiresAt) ? new Date(expiresAt).toISOString() : 'none';
}

/**
 * Runs `task` once for callers that overlap in time and shares its result. Used so that
 * several requests failing with 401 at once trigger one token renewal, not one each.
 * A failed run clears the slot, so the next caller retries.
 */
/** When the broker returns HTTP 200 without a token, maps JSON fields to a safe operator message. */
export function loginErrorFromBody(body: unknown): string | undefined {
  if (body === null || typeof body !== 'object') {
    return 'Dhan login failed: unexpected response shape';
  }
  const record = body as Record<string, unknown>;
  const token = record['accessToken'] ?? record['access_token'];
  if (typeof token === 'string' && token.length > 0) {
    return undefined;
  }
  for (const key of BROKER_ERROR_KEYS) {
    const value = record[key];
    if (typeof value === 'string' && value.length > 0) {
      return `Dhan login failed: ${value}`;
    }
  }
  const status = record['status'];
  if (typeof status === 'string' && status.length > 0 && status !== 'success') {
    return `Dhan login failed (status=${status})`;
  }
  return 'Dhan login failed: response did not contain an access token';
}

/** One extra login attempt used only after the SDK throws a token-less success body. */
export async function probeDhanLogin(request: {
  readonly clientId: string;
  readonly pin: string;
  readonly totp: string;
}): Promise<string | undefined> {
  const url = new URL('/app/generateAccessToken', DHAN_AUTH_BASE);
  url.searchParams.set('dhanClientId', request.clientId);
  url.searchParams.set('pin', request.pin);
  url.searchParams.set('totp', request.totp);
  const response = await fetch(url, {
    method: 'POST',
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  });
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    return `Dhan login failed: HTTP ${response.status} with a non-JSON body`;
  }
  const loginError = loginErrorFromBody(body);
  if (loginError !== undefined) {
    return loginError;
  }
  if (!response.ok) {
    return `Dhan login failed: HTTP ${response.status}`;
  }
  return undefined;
}

export async function clarifyDhanLoginFailure(
  error: unknown,
  probe: () => Promise<string | undefined>,
): Promise<Error> {
  if (error instanceof AuthenticationError) {
    return new Error(`Dhan login failed: ${error.message}`, { cause: error });
  }
  if (error instanceof Error) {
    const vague =
      error.message === 'Token response did not contain an accessToken' || error.message === 'Dhan login returned no token';
    if (vague) {
      const detail = await probe().catch(() => undefined);
      return new Error(
        detail ?? 'Dhan login failed: broker returned no access token (check DHAN_CLIENT_ID, DHAN_PIN, and DHAN_TOTP_SECRET)',
        { cause: error },
      );
    }
  }
  return error instanceof Error ? error : new Error(String(error));
}

export function singleFlight<T>(task: () => Promise<T>): () => Promise<T> {
  let inFlight: Promise<T> | undefined;
  return () => {
    inFlight ??= task().finally(() => {
      inFlight = undefined;
    });
    return inFlight;
  };
}

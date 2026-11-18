import type { Logger } from '../ops/logger.js';
import { singleFlight } from './auth.js';

/** How long before expiry the provider asks the authority again, so a token the authority replaced is picked up. */
const RENEW_MARGIN_MS = 5 * 60_000;
/**
 * Rails can replace the token well before its expiry (it renews 30 minutes early and force-refreshes on auth
 * errors), and the old token dies at once (DH-906). A held token older than this is re-read from the authority.
 */
const MAX_HELD_AGE_MS = 30_000;
const REQUEST_TIMEOUT_MS = 5_000;
const STARTUP_WAIT_MS = 10 * 60_000;
const STARTUP_RETRY_MS = 5_000;

/** The authority answered, and said no. Retrying with the same key cannot succeed, so startup does not wait on it. */
class AuthorityRejectedError extends Error {}

export interface AuthorityTokenOptions {
  /** The authority's token endpoint, for example http://127.0.0.1:3011/api/dhan/token. */
  readonly url: string;
  /** The authority's operator key. Sent as a bearer header and never logged. */
  readonly key: string;
  /** The Dhan client id this agent trades. A token for another client is refused. */
  readonly clientId: string;
  readonly startupWaitMs?: number;
  readonly fetch?: typeof fetch;
  readonly now?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
  readonly logger?: Logger;
}

export interface AuthorityTokenProvider {
  /** The SDK's `tokenProvider`. Cheap while the held token is valid; otherwise asks the authority. */
  readonly provide: () => Promise<string>;
  /** Startup gate: waits for the authority to come up, then fails with the standalone alternative. */
  readonly ensureReady: () => Promise<void>;
  /** For the SDK's `onTokenExpired`: refetch now. */
  readonly refresh: () => Promise<void>;
}

interface HeldToken {
  readonly accessToken: string;
  readonly expiresAt: number;
  readonly fetchedAt: number;
}

const defaultSleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Serves the Dhan token that another process (the Rails app) owns. Logging in here as well would invalidate
 * the owner's token (DH-906), so this never logs in. If the authority is down, a still-valid token keeps working;
 * once it expires, requests fail closed rather than silently falling back to a second login.
 */
export function createAuthorityTokenProvider(options: AuthorityTokenOptions): AuthorityTokenProvider {
  const doFetch = options.fetch ?? fetch;
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? defaultSleep;
  let held: HeldToken | undefined;
  let degradedWarned = false;

  const fetchToken = async (): Promise<HeldToken> => {
    const response = await doFetch(options.url, {
      headers: { Authorization: `Bearer ${options.key}` },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (response.status === 401 || response.status === 403) {
      throw new AuthorityRejectedError(
        `token authority rejected the operator key (HTTP ${response.status}); DHAN_TOKEN_AUTHORITY_KEY must equal that app's API_OPERATOR_TOKEN`,
      );
    }
    if (!response.ok) {
      throw new Error(`token authority answered HTTP ${response.status}`);
    }
    const parsed = parseToken(await response.json(), options.clientId);
    return { ...parsed, fetchedAt: now() };
  };

  // Several requests can find the token due at once. They must share one fetch.
  const fetchNow = singleFlight(async () => {
    const previous = held;
    held = await fetchToken();
    degradedWarned = false;
    logTokenChange(previous, held);
  });

  // Operators need proof the handshake worked and a record of each rotation; the token itself is never logged.
  const logTokenChange = (previous: HeldToken | undefined, current: HeldToken): void => {
    if (previous?.accessToken === current.accessToken) {
      return;
    }
    const expiresAt = new Date(current.expiresAt).toISOString();
    options.logger?.info(
      previous === undefined ? 'dhan token read from the token authority' : 'dhan token replaced by the token authority',
      { expiresAt },
    );
  };

  const isDue = (token: HeldToken): boolean =>
    now() - token.fetchedAt >= MAX_HELD_AGE_MS || now() >= token.expiresAt - RENEW_MARGIN_MS;

  /** Serving a held token while the authority is down is allowed only until that token expires. */
  const renewIfDue = async (): Promise<void> => {
    try {
      await fetchNow();
    } catch (error) {
      if (error instanceof AuthorityRejectedError) {
        throw error;
      }
      if (held !== undefined && now() < held.expiresAt) {
        if (!degradedWarned) {
          degradedWarned = true;
          options.logger?.warn('dhan token authority unreachable; using the held token until it expires', {
            error: error instanceof Error ? error.message : String(error),
          });
        }
        return;
      }
      throw new Error(`Dhan token authority is unreachable and no valid token is held: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  const provide = async (): Promise<string> => {
    if (held === undefined || isDue(held)) {
      await renewIfDue();
    }
    if (held === undefined) {
      throw new Error('Dhan token authority returned no token');
    }
    return held.accessToken;
  };

  const ensureReady = async (): Promise<void> => {
    const deadline = now() + (options.startupWaitMs ?? STARTUP_WAIT_MS);
    for (;;) {
      try {
        await provide();
        return;
      } catch (error) {
        if (error instanceof AuthorityRejectedError) {
          throw error;
        }
        if (now() >= deadline) {
          throw new Error(
            `${error instanceof Error ? error.message : String(error)}. Start the Rails app, or run this agent standalone by setting DHAN_PIN and DHAN_TOTP_SECRET instead of DHAN_TOKEN_AUTHORITY_URL (only one process may log in per Dhan account)`,
          );
        }
        options.logger?.info('waiting for the dhan token authority', { retryInMs: STARTUP_RETRY_MS });
        await sleep(STARTUP_RETRY_MS);
      }
    }
  };

  // The SDK calls this after a 401. It must fetch for real: falling back to the token just rejected would retry it.
  const refresh = async (): Promise<void> => {
    try {
      await fetchNow();
    } catch (error) {
      if (error instanceof AuthorityRejectedError) {
        throw error;
      }
      throw new Error(`Dhan token authority is unreachable after a 401: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  return { provide, ensureReady, refresh };
}

/** Validates the authority's reply. Messages name the problem and never echo the token. */
function parseToken(body: unknown, expectedClientId: string): Omit<HeldToken, 'fetchedAt'> {
  const record = typeof body === 'object' && body !== null ? (body as Record<string, unknown>) : {};
  const accessToken = record['access_token'];
  const expiresAt = Date.parse(String(record['expires_at']));
  if (typeof accessToken !== 'string' || accessToken.length === 0 || !Number.isFinite(expiresAt)) {
    throw new Error('token authority reply is missing access_token or expires_at');
  }
  if (String(record['client_id']) !== expectedClientId) {
    throw new Error('token authority issued a token for a different Dhan client id than DHAN_CLIENT_ID');
  }
  return { accessToken, expiresAt };
}

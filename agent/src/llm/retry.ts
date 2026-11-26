/**
 * Retry timing shared by the two trade advisors (chat and decision model), so both
 * wait the same way for the same kind of transient failure.
 */

/** Upper bound for any single wait between attempts, including a server Retry-After hint. */
export const MAX_RETRY_DELAY_MS = 8_000;

/** Exponential backoff with jitter: baseMs * 2^(attempt-1), capped, times 0.8..1.2. */
export function backoffDelayMs(attempt: number, baseMs: number): number {
  const jitter = 0.8 + Math.random() * 0.4;
  return Math.round(Math.min(baseMs * 2 ** (attempt - 1), MAX_RETRY_DELAY_MS) * jitter);
}

/** A positive server Retry-After hint (ms), capped; undefined when there is none. */
export function cappedRetryAfterMs(hintMs: number | undefined): number | undefined {
  return typeof hintMs === 'number' && hintMs > 0 ? Math.min(hintMs, MAX_RETRY_DELAY_MS) : undefined;
}

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

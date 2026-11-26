/**
 * Dhan's OpenAPI caps `correlationId` at 30 characters on regular and super orders (`OrderRequest` and
 * `SuperOrderRequest`). A longer id is refused by the broker, so the agent never sends one.
 */
export const BROKER_CORRELATION_MAX = 30;

export type CorrelationKind = 'E' | 'X' | 'P';

/**
 * A venue-safe order id: one letter for the kind (E entry, X agent exit, P protective exit), the time in base36,
 * and a per-process counter in base36. Unique within a process because the counter never repeats, and across
 * restarts because the time moves on. It stays at or under 13 characters, well inside the broker's limit.
 */
export function correlationIdFor(kind: CorrelationKind, nowMs: number, counter: number): string {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0 || !Number.isSafeInteger(counter) || counter < 0) {
    throw new RangeError('correlation id needs a non-negative time and counter');
  }
  return `${kind}${Math.floor(nowMs).toString(36)}${counter.toString(36)}`;
}

/** True when the id is non-empty and within the broker's limit. Checked before every send. */
export function fitsBrokerLimit(correlationId: string): boolean {
  return correlationId.length > 0 && correlationId.length <= BROKER_CORRELATION_MAX;
}

/**
 * Rejects if `promise` does not settle within `ms`. The promise itself is not cancelled, so a write that
 * finishes late can still land. Callers must treat a timeout as a failure they cannot undo.
 */
export function withDeadline<T>(promise: Promise<T>, ms: number, message: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => {
    clearTimeout(timer);
  });
}

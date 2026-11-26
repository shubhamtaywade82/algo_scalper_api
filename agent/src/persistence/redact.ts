/**
 * Connection strings carry passwords. Driver errors and log lines can echo them, so every error that
 * leaves the persistence layer passes through here first.
 */
export function redact(text: string, secrets: readonly string[] = []): string {
  // Userinfo can contain an unencoded '@'. The match runs to the last '@' before the path, not the first.
  let out = text.replace(/([a-z][a-z0-9+.-]*:\/\/)[^\s/]*@/gi, '$1***@');
  for (const secret of secrets) {
    if (secret.length > 0) {
      out = out.split(secret).join('***');
    }
  }
  return out;
}

/** Passwords and the raw URL for one connection string, for use as redaction secrets. */
export function secretsOf(url: string): string[] {
  const values = [url];
  try {
    const password = decodeURIComponent(new URL(url).password);
    if (password.length > 0) {
      values.push(password);
    }
  } catch {
    // The URL did not parse. The raw value is still in the list, so it is still redacted.
  }
  return values;
}

/** A bounded, redacted description of an error, safe to log or to show on the cockpit. */
export function errorMessage(error: unknown, secrets: readonly string[] = []): string {
  const raw = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  return redact(raw, secrets).slice(0, 300);
}

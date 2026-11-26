/**
 * NSE/BSE trade on India Standard Time (UTC+05:30, no DST). Every session,
 * expiry and cutoff rule in this codebase is evaluated on IST wall-clock values
 * derived here, never on the host's local timezone.
 */
export const IST_OFFSET_MS = 330 * 60_000;

/** Seconds offset applied when Dhan encodes IST wall-clock as epoch seconds. */
const IST_OFFSET_SECONDS = 19_800;

export interface IstParts {
  /** `YYYY-MM-DD` in IST. */
  readonly date: string;
  /** Minutes since IST midnight, 0..1439. */
  readonly minuteOfDay: number;
}

export function istParts(epochMs: number): IstParts {
  if (!Number.isFinite(epochMs)) {
    throw new RangeError(`invalid epoch ms: ${epochMs}`);
  }
  const shifted = new Date(epochMs + IST_OFFSET_MS);
  return {
    date: shifted.toISOString().slice(0, 10),
    minuteOfDay: shifted.getUTCHours() * 60 + shifted.getUTCMinutes(),
  };
}

const HH_MM = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** `"09:15"` → `555`. Rejects anything that is not a 24h `HH:MM` string. */
export function parseMinuteOfDay(value: string): number {
  const match = HH_MM.exec(value.trim());
  if (!match) {
    throw new Error(`expected 24h HH:MM time, got "${value}"`);
  }
  return Number(match[1]) * 60 + Number(match[2]);
}

export function formatMinuteOfDay(minuteOfDay: number): string {
  const hours = Math.floor(minuteOfDay / 60);
  const minutes = minuteOfDay % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

/** Adds whole calendar days to a `YYYY-MM-DD` key. Pure calendar arithmetic, no timezone. */
export function shiftDateKey(dateKey: string, days: number): string {
  const [year, month, day] = dateKey.split('-').map(Number) as [number, number, number];
  const shifted = new Date(Date.UTC(year, month - 1, day + days));
  return shifted.toISOString().slice(0, 10);
}

/**
 * Converts a Dhan epoch-seconds value to epoch milliseconds. When Dhan encodes
 * IST wall-clock into its epoch (`istShifted = true`), the 5h30m offset is
 * removed so the result is a true UTC instant. The mode is a configuration
 * switch because the convention is verified against live samples, not assumed.
 */
export function dhanEpochSecondsToMs(seconds: number, istShifted: boolean): number {
  const utcSeconds = istShifted ? seconds - IST_OFFSET_SECONDS : seconds;
  return utcSeconds * 1000;
}

/** NSE/BSE regular session opens at 09:15 IST. */
export const NSE_SESSION_OPEN_MINUTE = 9 * 60 + 15;
/** NSE/BSE regular session closes at 15:30 IST. */
export const NSE_SESSION_CLOSE_MINUTE = 15 * 60 + 30;

/** True when the IST instant falls within regular market hours (Monday–Friday 09:15–15:30). */
export function isMarketSessionOpen(epochMs: number): boolean {
  const shifted = new Date(epochMs + IST_OFFSET_MS);
  const day = shifted.getUTCDay();
  if (day === 0 || day === 6) {
    return false;
  }
  const minute = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  return minute >= NSE_SESSION_OPEN_MINUTE && minute < NSE_SESSION_CLOSE_MINUTE;
}

import { formatMinuteOfDay, istParts } from '../time/ist.js';

export type LogLevel = 'info' | 'warn' | 'error';

export interface Logger {
  info(message: string, data?: Readonly<Record<string, unknown>>): void;
  warn(message: string, data?: Readonly<Record<string, unknown>>): void;
  error(message: string, data?: Readonly<Record<string, unknown>>): void;
}

/** Console logger with IST timestamps, so terminal output lines up with NSE session times. */
export function createConsoleLogger(sink: (line: string) => void = console.log, now: () => number = Date.now): Logger {
  const write = (level: LogLevel, message: string, data?: Readonly<Record<string, unknown>>): void => {
    const parts = istParts(now());
    const stamp = `${parts.date} ${formatMinuteOfDay(parts.minuteOfDay)} IST`;
    const suffix = data === undefined ? '' : ` ${JSON.stringify(data)}`;
    sink(`${stamp} ${level.toUpperCase().padEnd(5)} ${message}${suffix}`);
  };
  return {
    info: (message, data) => write('info', message, data),
    warn: (message, data) => write('warn', message, data),
    error: (message, data) => write('error', message, data),
  };
}

export interface LogRecord {
  readonly ts: number;
  readonly level: LogLevel;
  readonly message: string;
  readonly data: Readonly<Record<string, unknown>> | undefined;
}

/**
 * Bounded in-memory log for the terminal cockpit. Console output would tear the full-screen
 * UI, so cockpit mode keeps the recent lines here and the screen reads them.
 */
export class RingLogger implements Logger {
  private readonly records: LogRecord[] = [];

  constructor(
    private readonly capacity = 200,
    private readonly now: () => number = Date.now,
  ) {}

  info(message: string, data?: Readonly<Record<string, unknown>>): void {
    this.push('info', message, data);
  }

  warn(message: string, data?: Readonly<Record<string, unknown>>): void {
    this.push('warn', message, data);
  }

  error(message: string, data?: Readonly<Record<string, unknown>>): void {
    this.push('error', message, data);
  }

  /** Most recent records first. */
  newest(limit: number): readonly LogRecord[] {
    return this.records.slice(-limit).reverse();
  }

  private push(level: LogLevel, message: string, data: Readonly<Record<string, unknown>> | undefined): void {
    this.records.push({ ts: this.now(), level, message, data });
    if (this.records.length > this.capacity) {
      this.records.splice(0, this.records.length - this.capacity);
    }
  }
}

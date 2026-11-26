import type { Candle, Tick } from '../domain/types.js';
import { IST_OFFSET_MS, istParts, NSE_SESSION_CLOSE_MINUTE, NSE_SESSION_OPEN_MINUTE } from '../time/ist.js';

const DAY_MS = 86_400_000;
const SESSION_OPEN_MS = NSE_SESSION_OPEN_MINUTE * 60_000;

/**
 * Ordered, bounded bar history. Re-appending the bar at the same open time
 * replaces it, so a warmup bar that overlaps the live feed never duplicates.
 */
export class BarSeries {
  private readonly bars: Candle[] = [];

  constructor(private readonly capacity = 2_000) {}

  get length(): number {
    return this.bars.length;
  }

  get last(): Candle | undefined {
    return this.bars[this.bars.length - 1];
  }

  all(): readonly Candle[] {
    return this.bars;
  }

  /** Returns false (and changes nothing) when the bar is older than the newest stored bar. */
  upsert(candle: Candle): boolean {
    const last = this.last;
    if (last !== undefined && candle.time < last.time) {
      return false;
    }
    if (last !== undefined && candle.time === last.time) {
      this.bars[this.bars.length - 1] = candle;
      return true;
    }
    this.bars.push(candle);
    if (this.bars.length > this.capacity) {
      this.bars.splice(0, this.bars.length - this.capacity);
    }
    return true;
  }
}

/**
 * Aggregates LTP ticks into closed bars aligned to IST wall-clock boundaries.
 * Ticker-mode feeds carry no per-trade volume, so bar volume is 0 by design and
 * no strategy here depends on it.
 */
export class CandleBuilder {
  private open: { time: number; open: number; high: number; low: number; close: number } | undefined;
  /** Start of the newest bar already emitted. Dhan stamps ticks in whole seconds and they arrive after the
   * wall-clock flush, so a late tick must not reopen that bucket and replace the full bar with a one-tick bar. */
  private lastClosedTime: number | undefined;
  private lateTicks = 0;

  constructor(private readonly barMs: number) {
    if (!Number.isInteger(barMs) || barMs <= 0) {
      throw new RangeError(`bar size must be a positive integer of ms, got ${barMs}`);
    }
  }

  get droppedLateTicks(): number {
    return this.lateTicks;
  }

  /**
   * Buckets count from the 09:15 IST open, as Dhan's intraday history does. Counting from midnight agreed only for
   * bar sizes that divide 555 minutes: 25- and 60-minute live bars would not line up with the warmup bars.
   */
  bucketStart(epochMs: number): number {
    const istMs = epochMs + IST_OFFSET_MS;
    const sessionOpenMs = Math.floor(istMs / DAY_MS) * DAY_MS + SESSION_OPEN_MS;
    return sessionOpenMs + Math.floor((istMs - sessionOpenMs) / this.barMs) * this.barMs - IST_OFFSET_MS;
  }

  /** Feeds one tick; returns the bar that closed because this tick opened a new bucket. */
  onTick(tick: Pick<Tick, 'ltp' | 'ltt'>): Candle | undefined {
    if (!Number.isFinite(tick.ltp) || tick.ltp <= 0 || !Number.isFinite(tick.ltt)) {
      return undefined;
    }
    // Pre-open and post-close index values have no bar in Dhan's history, so live bars leave them out too.
    const minute = istParts(tick.ltt).minuteOfDay;
    if (minute < NSE_SESSION_OPEN_MINUTE || minute >= NSE_SESSION_CLOSE_MINUTE) {
      return undefined;
    }
    const bucket = this.bucketStart(tick.ltt);
    if ((this.lastClosedTime !== undefined && bucket <= this.lastClosedTime) || (this.open !== undefined && bucket < this.open.time)) {
      this.lateTicks += 1;
      return undefined;
    }
    if (this.open === undefined) {
      this.open = { time: bucket, open: tick.ltp, high: tick.ltp, low: tick.ltp, close: tick.ltp };
      return undefined;
    }
    if (bucket === this.open.time) {
      this.open.high = Math.max(this.open.high, tick.ltp);
      this.open.low = Math.min(this.open.low, tick.ltp);
      this.open.close = tick.ltp;
      return undefined;
    }
    const closed = this.toCandle(this.open);
    this.open = { time: bucket, open: tick.ltp, high: tick.ltp, low: tick.ltp, close: tick.ltp };
    return closed;
  }

  /** Closes the open bar once wall-clock time has passed its end, so quiet markets still produce bars. */
  flush(nowMs: number): Candle | undefined {
    if (this.open === undefined || nowMs < this.open.time + this.barMs) {
      return undefined;
    }
    const closed = this.toCandle(this.open);
    this.open = undefined;
    return closed;
  }

  private toCandle(bar: { time: number; open: number; high: number; low: number; close: number }): Candle {
    this.lastClosedTime = bar.time;
    return { time: bar.time, open: bar.open, high: bar.high, low: bar.low, close: bar.close, volume: 0 };
  }
}

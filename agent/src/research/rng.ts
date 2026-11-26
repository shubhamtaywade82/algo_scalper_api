/**
 * Seeded PRNG (mulberry32). Every resampling run is reproducible from its seed on any machine, so a reported
 * interval can always be re-derived. Not for cryptography.
 */
export class SeededRng {
  private state: number;

  constructor(seed: number) {
    if (!Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) {
      throw new RangeError(`seed must be an integer in [0, 2^32), got ${seed}`);
    }
    this.state = seed >>> 0;
  }

  /** Uniform in [0, 1). */
  next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  }

  /** Uniform integer in [0, n). */
  int(n: number): number {
    if (!Number.isInteger(n) || n <= 0) {
      throw new RangeError(`range must be a positive integer, got ${n}`);
    }
    return Math.floor(this.next() * n);
  }
}

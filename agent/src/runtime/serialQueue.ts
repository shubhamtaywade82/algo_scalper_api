/**
 * Runs tasks strictly one after another. Each underlying agent funnels market
 * events, execution events and timers through one queue, so transitions never
 * interleave even though the underlying I/O is asynchronous.
 */
export class SerialQueue {
  private tail: Promise<void> = Promise.resolve();

  constructor(private readonly onError: (error: unknown) => void) {}

  run(task: () => Promise<void>): void {
    this.tail = this.tail.then(task).catch((error: unknown) => {
      this.onError(error);
    });
  }

  drain(): Promise<void> {
    return this.tail;
  }
}

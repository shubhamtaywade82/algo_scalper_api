/** Second Ctrl+C within this window triggers an immediate quit. */
export const OPERATOR_INTERRUPT_ARM_MS = 2_000;

let armedAt = 0;
let lastCallMs = 0;

/** First call arms; a second call inside the window confirms an immediate quit. */
export function operatorInterrupt(nowMs: number = Date.now()): 'armed' | 'confirmed' {
  if (nowMs === lastCallMs) {
    return 'armed';
  }
  lastCallMs = nowMs;
  if (armedAt > 0 && nowMs - armedAt < OPERATOR_INTERRUPT_ARM_MS) {
    armedAt = 0;
    return 'confirmed';
  }
  armedAt = nowMs;
  return 'armed';
}

export function resetOperatorInterrupt(): void {
  armedAt = 0;
}

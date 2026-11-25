import { describe, it, expect } from 'vitest';
import { createSessionState, getFormingValues, pushLiveTick } from './engine';

const FIVE_MIN = 300e3;
// 2026-11-25 10:00 IST == 04:30 UTC
const BAR_START = Date.UTC(2026, 10, 25, 4, 30);

function stateWithOneBar(tf = 5, startMs = BAR_START) {
  const state = createSessionState(1, tf, 'NIFTY');
  const path = new Array(12).fill(100);
  state.bars = [{ t: startMs, o: 100, h: 101, l: 99, c: 100, v: 10, path }];
  state.playhead = 0;
  return state;
}

describe('pushLiveTick', () => {
  it('should update the forming bar when the tick falls inside its interval', () => {
    const state = stateWithOneBar();
    const result = pushLiveTick(state, 102, BAR_START + 60e3);
    expect(result).toBe('updated');
    expect(state.bars[0]).toMatchObject({ c: 102, h: 102, l: 99 });
  });

  it('should roll a new bar when the interval has elapsed', () => {
    const state = stateWithOneBar();
    const result = pushLiveTick(state, 103, BAR_START + FIVE_MIN + 1000);
    expect(result).toBe('rolled');
    expect(state.bars).toHaveLength(2);
    expect(state.bars[1]).toMatchObject({ t: BAR_START + FIVE_MIN, o: 103, c: 103 });
    expect(state.playhead).toBe(1);
  });

  it('should ask for a reload when more than one interval was missed', () => {
    const state = stateWithOneBar();
    expect(pushLiveTick(state, 103, BAR_START + 3 * FIVE_MIN)).toBe('reload');
    expect(state.bars).toHaveLength(1);
  });

  it('should not roll a bar outside the cash session', () => {
    const lastBar = Date.UTC(2026, 10, 25, 9, 55); // 15:25 IST, next bar would open at 15:30
    const state = stateWithOneBar(5, lastBar);
    pushLiveTick(state, 104, lastBar + FIVE_MIN + 1000);
    expect(state.bars).toHaveLength(1);
  });

  it('should ignore non-numeric ticks', () => {
    const state = stateWithOneBar();
    expect(pushLiveTick(state, NaN, BAR_START)).toBeNull();
    expect(state.bars[0].c).toBe(100);
  });
});

describe('getFormingValues', () => {
  it('should report the live close, not the open, for the latest bar', () => {
    const state = stateWithOneBar();
    pushLiveTick(state, 102.5, BAR_START + 1000);
    expect(getFormingValues(state).cur).toBe(102.5);
  });
});

import { describe, it, expect } from 'vitest';
import { clampCenter, followCenter, hitZone, scalePrice, zoomAt, MIN_VISIBLE_BARS } from './interaction';

const plot = { x: 8, y: 8, w: 800, h: 500, r: 808, b: 508 };
const makeView = () => ({ center: 100, visible: 80, minP: 100, maxP: 200 });
const barUnder = (view, px) => view.center - view.visible / 2 + (px - plot.x) / (plot.w / view.visible);

describe('zoomAt', () => {
  it('should keep the bar under the cursor fixed when zooming', () => {
    const view = makeView(), before = barUnder(view, 300);
    zoomAt(view, plot, 300, 0.5);
    expect(view.visible).toBe(40);
    expect(barUnder(view, 300)).toBeCloseTo(before, 6);
  });

  it('should not zoom in past the minimum number of bars', () => {
    const view = makeView();
    zoomAt(view, plot, 300, 0.0001);
    expect(view.visible).toBe(MIN_VISIBLE_BARS);
  });
});

describe('view bounds', () => {
  it('should keep the newest bar in view with a right margin when following', () => {
    const view = makeView();
    expect(view.center + view.visible / 2).toBeLessThan(followCenter(view, 300) + view.visible / 2);
    expect(followCenter(view, 300) + view.visible / 2).toBe(310);
  });

  it('should not let the chart scroll entirely off the data', () => {
    const view = makeView();
    view.center = 100000;
    clampCenter(view, 300);
    expect(view.center - view.visible / 2).toBeLessThanOrEqual(300 + view.visible * 0.6 - view.visible);
  });
});

describe('price scale', () => {
  it('should scale around the middle of the visible range', () => {
    const view = makeView();
    scalePrice(view, 2);
    expect([view.minP, view.maxP]).toEqual([50, 250]);
  });
});

describe('hitZone', () => {
  it('should classify the price axis, time axis and plot', () => {
    expect(hitZone(900, 100, plot)).toBe('priceAxis');
    expect(hitZone(300, 520, plot)).toBe('timeAxis');
    expect(hitZone(300, 100, plot)).toBe('plot');
  });
});

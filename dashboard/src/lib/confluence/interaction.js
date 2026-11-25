import { clamp } from './engine';

export const MIN_VISIBLE_BARS = 10;
export const MAX_VISIBLE_BARS = 800;
const MAX_RIGHT_MARGIN_BARS = 10;
const WHEEL_ZOOM_SENSITIVITY = 0.0015;
const PINCH_WHEEL_SENSITIVITY = 0.01;
const AXIS_DRAG_SENSITIVITY = 0.004;
const VERTICAL_PAN_LOCK_PX = 3;
const KEY_PAN_BARS = 5;
const KEY_PAN_BARS_FAST = 20;
const KEY_ZOOM_FACTOR = 1.25;
const LINE_HEIGHT_PX = 16;

export function hitZone(px, py, plot) {
  if (px > plot.r) return 'priceAxis';
  if (py > plot.b) return 'timeAxis';
  return 'plot';
}

const barWidth = (view, plot) => plot.w / view.visible;

/** Zooms the time axis while keeping the bar under `anchorPx` stationary. */
export function zoomAt(view, plot, anchorPx, factor) {
  const anchorBar = view.center - view.visible / 2 + (anchorPx - plot.x) / barWidth(view, plot);
  view.visible = clamp(view.visible * factor, MIN_VISIBLE_BARS, MAX_VISIBLE_BARS);
  view.center = anchorBar - (anchorPx - plot.x) / barWidth(view, plot) + view.visible / 2;
}

export function scalePrice(view, factor) {
  const mid = (view.minP + view.maxP) / 2, half = ((view.maxP - view.minP) / 2) * factor;
  view.minP = mid - half;
  view.maxP = mid + half;
}

/** Centre of the view that shows the newest bar with a small empty margin on the right. */
export function followCenter(view, barCount) {
  return barCount + Math.min(MAX_RIGHT_MARGIN_BARS, view.visible * 0.3) - view.visible / 2;
}

export function clampCenter(view, barCount) {
  if (!barCount) return;
  const half = view.visible / 2;
  view.center = clamp(view.center, half - view.visible * 0.4, barCount + view.visible * 0.6 - half);
}

const wheelDelta = (e) => (e.deltaMode === 1 ? e.deltaY * LINE_HEIGHT_PX : e.deltaY);
const isTypingTarget = (t) => /^(INPUT|SELECT|TEXTAREA)$/.test(t?.tagName || '');

function localPoint(e) {
  const r = e.currentTarget.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}

function pinchDistance(pointers) {
  const [a, b] = [...pointers.values()];
  return { dist: Math.hypot(a.x - b.x, a.y - b.y) || 1, midX: (a.x + b.x) / 2 };
}

function dragPlot(ctx, drag, p) {
  const view = ctx.view(), plot = ctx.plot(), dx = p.x - drag.x, dy = p.y - drag.y;
  if (Math.abs(dx) > 2) ctx.setFollowing(false);
  view.center = drag.center - dx / barWidth(view, plot);
  if (Math.abs(dy) > VERTICAL_PAN_LOCK_PX) ctx.setAutoScale(false);
  if (ctx.autoScale()) return;
  const shift = (dy * (drag.maxP - drag.minP)) / plot.h;
  view.minP = drag.minP + shift;
  view.maxP = drag.maxP + shift;
}

function dragAxis(ctx, drag, p) {
  const view = ctx.view(), plot = ctx.plot();
  if (drag.zone === 'priceAxis') {
    ctx.setAutoScale(false);
    view.minP = drag.minP; view.maxP = drag.maxP;
    scalePrice(view, Math.exp((p.y - drag.y) * AXIS_DRAG_SENSITIVITY));
    return;
  }
  zoomAt(view, plot, plot.r, Math.exp(-(p.x - drag.lastX) * AXIS_DRAG_SENSITIVITY));
  drag.lastX = p.x;
}

function applyWheel(ctx, e, p) {
  const view = ctx.view(), plot = ctx.plot(), delta = wheelDelta(e), zone = hitZone(p.x, p.y, plot);
  if (zone === 'priceAxis') {
    ctx.setAutoScale(false);
    scalePrice(view, Math.exp(delta * WHEEL_ZOOM_SENSITIVITY));
  } else if (e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
    ctx.setFollowing(false);
    view.center += (e.shiftKey ? delta : e.deltaX) / barWidth(view, plot);
  } else {
    const sensitivity = e.ctrlKey ? PINCH_WHEEL_SENSITIVITY : WHEEL_ZOOM_SENSITIVITY;
    zoomAt(view, plot, ctx.following() ? plot.r : p.x, Math.exp(delta * sensitivity));
  }
}

/**
 * TradingView-style pointer, wheel, pinch and keyboard handling over a shared mutable `view`.
 * `ctx` supplies view/plot accessors plus follow/auto-scale state and redraw hooks.
 */
export function createGestures(ctx) {
  const pointers = new Map();
  let drag = null, pinch = null;
  const refresh = () => { clampCenter(ctx.view(), ctx.barCount()); ctx.markDirty(); };
  const cursorFor = (zone) => (zone === 'priceAxis' ? 'ns-resize' : zone === 'timeAxis' ? 'ew-resize' : 'crosshair');

  function onPointerDown(e) {
    // Pointer capture would retarget the click away from overlay buttons (AUTO, RESET, LATEST).
    if (e.target.closest('button')) return;
    const p = localPoint(e), view = ctx.view();
    e.currentTarget.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, p);
    if (pointers.size === 2) { pinch = pinchDistance(pointers); drag = null; return; }
    drag = { zone: hitZone(p.x, p.y, ctx.plot()), x: p.x, y: p.y, lastX: p.x, center: view.center, minP: view.minP, maxP: view.maxP };
    if (drag.zone === 'plot') ctx.setCursor('grabbing');
  }

  function onPointerMove(e) {
    const p = localPoint(e);
    if (pointers.has(e.pointerId)) pointers.set(e.pointerId, p);
    if (pinch && pointers.size === 2) {
      const next = pinchDistance(pointers);
      zoomAt(ctx.view(), ctx.plot(), ctx.following() ? ctx.plot().r : next.midX, pinch.dist / next.dist);
      pinch = next;
    } else if (drag) {
      (drag.zone === 'plot' ? dragPlot : dragAxis)(ctx, drag, p);
    } else {
      ctx.setCursor(cursorFor(hitZone(p.x, p.y, ctx.plot())));
    }
    ctx.setHover(drag?.zone === 'plot' ? null : p);
    refresh();
  }

  function onPointerEnd(e) {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinch = null;
    drag = null;
    ctx.setCursor('crosshair');
  }

  function onWheel(e) {
    e.preventDefault();
    applyWheel(ctx, e, localPoint(e));
    refresh();
  }

  function onKeyDown(e) {
    if (isTypingTarget(e.target) || e.ctrlKey || e.metaKey) return;
    const view = ctx.view(), plot = ctx.plot();
    const step = (e.shiftKey ? KEY_PAN_BARS_FAST : KEY_PAN_BARS) * (e.key === 'ArrowLeft' ? -1 : 1);
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { ctx.setFollowing(false); view.center += step; }
    else if (e.key === '+' || e.key === '=') zoomAt(view, plot, plot.r, 1 / KEY_ZOOM_FACTOR);
    else if (e.key === '-') zoomAt(view, plot, plot.r, KEY_ZOOM_FACTOR);
    else if (e.key === 'End') ctx.goLive();
    else if (e.altKey && e.code === 'KeyR') ctx.resetView();
    else return;
    e.preventDefault();
    refresh();
  }

  return { onPointerDown, onPointerMove, onPointerEnd, onWheel, onKeyDown, isDragging: () => drag?.zone === 'plot' };
}

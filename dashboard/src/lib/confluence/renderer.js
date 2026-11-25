import { clamp, lerp, NORMAL, REF } from './engine';

export const PALETTES = {
  ion: { bid: ['#07202E', '#0B5F79', '#12C2B0', '#B8FFF0'], ask: ['#26071C', '#8A1B4B', '#FF4D6D', '#FFD9C9'] },
  classic: { bid: ['#04231A', '#0B6B41', '#22D07E', '#D9FFE9'], ask: ['#2A060E', '#99142F', '#FF5A52', '#FFE2CE'] },
  ultra: { bid: ['#120A33', '#4327A8', '#8F7BFF', '#E9E4FF'], ask: ['#2B1204', '#A85A08', '#FFB224', '#FFF1CF'] }
};

export const C = {
  bid: '#19E3B1', ask: '#FF4D6D', amber: '#FFB224', cyan: '#3FC1FF', lime: '#9BE84C', violet: '#8F7BFF',
  text: '#E9EFFA', muted: '#8CA0BF', faint: '#5A6C8C', grid: '#131F36', grid2: '#1B2B4A', surface: '#0B1424', surface2: '#101C30'
};

const INR_FMT = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const fmtP = (p) => (Number.isFinite(Number(p)) && p != null ? INR_FMT.format(Number(p)) : '--');
export const fmtS = (s) => (s >= 1000 ? (s / 1000).toFixed(1) + 'k' : Math.round(s) + '');
// Bars are NSE session times; format in IST regardless of the viewer's timezone.
const IST_TIME = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit', hour12: false });
const IST_DAY = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short' });
export const fmtT = (t) => IST_TIME.format(new Date(t));
export const fmtD = (t) => IST_DAY.format(new Date(t));
export const fmtCountdown = (ms) => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0');
};

const hexRGB = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const mix = (h1, h2, t) => {
  const a = hexRGB(h1), b = hexRGB(h2);
  return [Math.round(lerp(a[0], b[0], t)), Math.round(lerp(a[1], b[1], t)), Math.round(lerp(a[2], b[2], t))];
};
const ramp = (stops, t) => {
  const n = stops.length - 1, i = Math.min(n - 1, Math.floor(t * n));
  return mix(stops[i], stops[i + 1], t * n - i);
};

export function buildLUT(paletteKey) {
  const pal = PALETTES[paletteKey] || PALETTES.ion, lut = { bid: [], ask: [] };
  for (const side of ['bid', 'ask']) {
    for (let i = 0; i < 12; i++) {
      const t = (i + 0.5) / 12, r = ramp(pal[side], t), a = 0.1 + 0.88 * Math.pow(t, 1.05);
      lut[side].push(`rgba(${r[0]},${r[1]},${r[2]},${a.toFixed(3)})`);
    }
  }
  return lut;
}

export const getX = (i, view, plot) => plot.x + (i - (view.center - view.visible / 2)) * (plot.w / view.visible);
export const getY = (p, view, plot) => plot.y + ((view.maxP - p) / (view.maxP - view.minP)) * plot.h;

function roundRect(ctx, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + r, y, r);
  ctx.closePath();
}

export function drawGrid(ctx, view, plot, bars, dpr, bw, axisW) {
  const range = view.maxP - view.minP;
  const steps = [0.05, 0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 200, 500];
  const pstep = steps.find((s) => range / s <= 10) || 50;
  ctx.font = '10px monospace'; ctx.strokeStyle = C.grid; ctx.lineWidth = 1;
  ctx.fillStyle = C.faint; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
  for (let p = Math.ceil(view.minP / pstep) * pstep; p <= view.maxP; p += pstep) {
    const y = Math.round(getY(p, view, plot)) + 0.5;
    ctx.beginPath(); ctx.moveTo(plot.x, y); ctx.lineTo(plot.r, y); ctx.stroke();
    ctx.fillText(fmtP(p), plot.r + 7, y);
  }
  const k = Math.max(1, Math.ceil(84 / bw)), left = view.center - view.visible / 2;
  const i0 = Math.max(0, Math.floor(left) - 1), i1 = Math.min(bars.length - 1, Math.ceil(left + view.visible) + 1);
  drawDaySeparators(ctx, view, plot, bars, i0, i1);
  for (let i = Math.ceil(i0 / k) * k; i <= i1; i += k) {
    if (!bars[i]) continue;
    const x = Math.round(getX(i, view, plot) + bw / 2) + 0.5;
    ctx.strokeStyle = C.grid;
    ctx.beginPath(); ctx.moveTo(x, plot.y); ctx.lineTo(x, plot.b); ctx.stroke();
    ctx.fillStyle = C.faint; ctx.textAlign = 'center';
    ctx.fillText(fmtT(bars[i].t), x, plot.b + 13);
  }
}

function drawDaySeparators(ctx, view, plot, bars, i0, i1) {
  ctx.strokeStyle = C.grid2; ctx.fillStyle = C.muted; ctx.textAlign = 'left'; ctx.font = '600 9px monospace';
  for (let i = Math.max(1, i0); i <= i1; i++) {
    if (!bars[i] || fmtD(bars[i].t) === fmtD(bars[i - 1].t)) continue;
    const x = Math.round(getX(i, view, plot)) + 0.5;
    ctx.setLineDash([2, 4]);
    ctx.beginPath(); ctx.moveTo(x, plot.y); ctx.lineTo(x, plot.b); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillText(fmtD(bars[i].t), x + 4, plot.y + 10);
  }
  ctx.font = '10px monospace';
}

export function drawLastPriceLine(ctx, plot, y, color) {
  if (y < plot.y || y > plot.b) return;
  ctx.strokeStyle = color; ctx.globalAlpha = 0.55; ctx.setLineDash([2, 3]);
  ctx.beginPath(); ctx.moveTo(plot.x, Math.round(y) + 0.5); ctx.lineTo(plot.r, Math.round(y) + 0.5); ctx.stroke();
  ctx.setLineDash([]); ctx.globalAlpha = 1;
}

export function drawHeatmap(ctx, view, plot, state, params, aggData, lut, bw) {
  if (!params.heat) return;
  const left = view.center - view.visible / 2;
  const i0 = Math.max(0, Math.floor(left) - 1);
  const i1 = Math.min(Math.floor(state.playhead) - 1, state.bars.length - 1, Math.ceil(left + view.visible) + 1);
  const range = view.maxP - view.minP, binPx = Math.max(1, (params.bin / range) * plot.h);
  const paths = { bid: Array.from({ length: 12 }, () => new Path2D()), ask: Array.from({ length: 12 }, () => new Path2D()) };
  for (let i = i0; i <= i1; i++) {
    const m = aggData[i];
    if (!m) continue;
    const close = state.bars[i].c, x = getX(i, view, plot);
    for (const [ai, s] of m) {
      const p = ai * params.bin;
      if (p < view.minP - params.bin || p > view.maxP + params.bin) continue;
      const t = Math.pow(Math.min(1, s / REF), params.gamma), bk = Math.min(11, (t * 12) | 0);
      paths[p < close ? 'bid' : 'ask'][bk].rect(x, getY(p + params.bin / 2, view, plot), bw + 0.6, binPx);
    }
  }
  for (const side of ['bid', 'ask']) {
    for (let b = 0; b < 12; b++) { ctx.fillStyle = lut[side][b]; ctx.fill(paths[side][b]); }
  }
}

const MAX_ZONES_PER_KIND = 4;

function firstBarIndexAt(bars, timeMs) {
  let lo = 0, hi = bars.length;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (bars[mid].t < timeMs) lo = mid + 1; else hi = mid; }
  return lo;
}

// An order block is dead once a later bar closes through it.
function isOrderBlockAlive(ob, bars, from) {
  for (let i = from + 1; i < bars.length; i++) {
    if (ob.side === 'bull' ? bars[i].c < ob.lo : bars[i].c > ob.hi) return false;
  }
  return true;
}

function drawZone(ctx, view, plot, x0, zone, rgb) {
  const y0 = getY(zone.hi, view, plot), y1 = getY(zone.lo, view, plot);
  if (y1 < plot.y || y0 > plot.b || x0 > plot.r) return;
  const x = Math.max(plot.x, x0);
  ctx.fillStyle = `rgba(${rgb},0.10)`; ctx.fillRect(x, y0, plot.r - x, y1 - y0);
  ctx.strokeStyle = `rgba(${rgb},0.55)`; ctx.setLineDash([4, 4]);
  ctx.beginPath(); ctx.moveTo(x, y0 + 0.5); ctx.lineTo(plot.r, y0 + 0.5); ctx.moveTo(x, y1 - 0.5); ctx.lineTo(plot.r, y1 - 0.5); ctx.stroke();
  ctx.setLineDash([]);
}

// Zones start at the bar that formed them and only the few nearest to price are drawn, so the chart stays readable.
function drawZones(ctx, view, plot, state, zones, rgbBySide, isAlive) {
  const mid = (view.minP + view.maxP) / 2;
  const live = zones.map((z) => ({ z, from: firstBarIndexAt(state.bars, z.startTime) })).filter(({ z, from }) => isAlive(z, from));
  live.sort((a, b) => Math.abs((a.z.lo + a.z.hi) / 2 - mid) - Math.abs((b.z.lo + b.z.hi) / 2 - mid));
  for (const { z, from } of live.slice(0, MAX_ZONES_PER_KIND)) drawZone(ctx, view, plot, getX(from, view, plot), z, rgbBySide[z.side]);
}

export function drawFvgAndRays(ctx, view, plot, state, params) {
  const rgb = { bull: '25,227,177', bear: '255,77,109' };
  if (params.ob && state.orderBlocks) drawZones(ctx, view, plot, state, state.orderBlocks, rgb, (ob, from) => isOrderBlockAlive(ob, state.bars, from));
  if (params.fvg && state.zones) drawZones(ctx, view, plot, state, state.zones, rgb, (z) => !z.filled);
  for (const p of state.pools || []) {
    const y = Math.round(getY(p.level, view, plot)) + 0.5;
    if (p.swept || y < plot.y || y > plot.b) continue;
    ctx.strokeStyle = p.type === 'BSL' ? C.cyan : C.amber; ctx.globalAlpha = 0.5; ctx.setLineDash([2, 3]);
    ctx.beginPath(); ctx.moveTo(plot.x, y); ctx.lineTo(plot.r, y); ctx.stroke();
    ctx.setLineDash([]); ctx.globalAlpha = 1;
  }
}

export function drawKeyLevelsAndPositions(ctx, view, plot, { levels, positions } = {}) {
  if (levels?.support) {
    const y = Math.round(getY(levels.support, view, plot)) + 0.5;
    if (y >= plot.y && y <= plot.b) {
      ctx.strokeStyle = '#10B981'; ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(plot.x, y); ctx.lineTo(plot.r, y); ctx.stroke();
      ctx.setLineDash([]);
    }
  }
  if (levels?.resistance) {
    const y = Math.round(getY(levels.resistance, view, plot)) + 0.5;
    if (y >= plot.y && y <= plot.b) {
      ctx.strokeStyle = '#FF4D6D'; ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(plot.x, y); ctx.lineTo(plot.r, y); ctx.stroke();
      ctx.setLineDash([]);
    }
  }
  if (positions?.length) {
    for (const p of positions) {
      const entry = Number(p.entry_price || p.buy_price);
      if (!Number.isFinite(entry)) continue;
      const y = Math.round(getY(entry, view, plot)) + 0.5;
      if (y < plot.y || y > plot.b) continue;
      ctx.strokeStyle = '#3FC1FF'; ctx.setLineDash([3, 3]);
      ctx.beginPath(); ctx.moveTo(plot.x, y); ctx.lineTo(plot.r, y); ctx.stroke();
      ctx.setLineDash([]);
    }
  }
}

export function drawCandlesAndVolume(ctx, view, plot, state, params, i0, i1, bw) {
  if (params.vol && i1 >= i0) {
    let vmax = 1;
    for (let i = i0; i <= i1; i++) if (state.bars[i]) vmax = Math.max(vmax, state.bars[i].v);
    const vh = plot.h * 0.15;
    for (let i = i0; i <= i1; i++) {
      const b = state.bars[i];
      if (!b) continue;
      ctx.fillStyle = b.c >= b.o ? 'rgba(25,227,177,0.32)' : 'rgba(255,77,109,0.32)';
      ctx.fillRect(getX(i, view, plot), plot.b - (b.v / vmax) * vh, Math.max(1, bw * 0.66), (b.v / vmax) * vh);
    }
  }
  const bodyW = clamp(bw * 0.62, 2, 15);
  for (let i = i0; i <= i1; i++) {
    const b = state.bars[i];
    if (!b) continue;
    const up = b.c >= b.o, col = up ? C.bid : C.ask, x = getX(i, view, plot) + bw / 2;
    const yo = getY(b.o, view, plot), yc = getY(b.c, view, plot);
    ctx.strokeStyle = col;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, getY(b.h, view, plot));
    ctx.lineTo(x, getY(b.l, view, plot));
    ctx.stroke();
    ctx.fillStyle = params.candle === 'hollow' && up ? 'rgba(7,13,26,0.85)' : col;
    ctx.fillRect(x - bodyW / 2, Math.min(yo, yc), bodyW, Math.max(1.2, Math.abs(yo - yc)));
    if (params.candle === 'hollow' && up) {
      ctx.strokeRect(x - bodyW / 2 + 0.5, Math.min(yo, yc) + 0.5, bodyW - 1, Math.max(1.2, Math.abs(yo - yc)) - 1);
    }
  }
}

export function drawChips(ctx, plot, axisW, chips) {
  chips.sort((a, b) => a.y0 - b.y0);
  for (const ch of chips) ch.y = clamp(ch.y0, plot.y + 8, plot.b - 8);
  for (let i = 1; i < chips.length; i++) {
    if (chips[i].y < chips[i - 1].y + chips[i - 1].h + 2) chips[i].y = chips[i - 1].y + chips[i - 1].h + 2;
  }
  ctx.font = '600 9px monospace';
  ctx.textBaseline = 'middle';
  for (const ch of chips) {
    const tw = ctx.measureText(ch.txt).width + 10, x = plot.r + 2;
    roundRect(ctx, x, ch.y, Math.min(axisW - 4, tw), ch.h, 4);
    ctx.fillStyle = ch.bg;
    ctx.fill();
    ctx.fillStyle = ch.fg;
    ctx.textAlign = 'left';
    ctx.fillText(ch.txt, x + 5, ch.y + ch.h / 2 + 0.5);
  }
}

export function drawDepthProfile(ctx, plot, view, aggMap, lastPrice, bin, maxDepthW) {
  const range = view.maxP - view.minP, binPx = Math.max(1.5, (bin / range) * plot.h - 1);
  let maxS = 1;
  for (const s of aggMap.values()) maxS = Math.max(maxS, s);
  for (const [ai, s] of aggMap) {
    const p = ai * bin;
    if (p < view.minP || p > view.maxP) continue;
    const t = Math.pow(s / maxS, 0.7), w = t * maxDepthW, y = getY(p + bin / 2, view, plot);
    ctx.fillStyle = p < lastPrice ? `rgba(25,227,177,${0.22 + 0.55 * t})` : `rgba(255,77,109,${0.22 + 0.55 * t})`;
    ctx.fillRect(plot.r - w, y, w, binPx);
  }
}

export function drawCrosshair(ctx, hover, plot, view, axisW, bars, bw) {
  const { px, py } = hover;
  if (px <= plot.x || px >= plot.r || py <= plot.y || py >= plot.b) return;
  ctx.strokeStyle = C.muted; ctx.globalAlpha = 0.5; ctx.setLineDash([3, 4]);
  ctx.beginPath();
  ctx.moveTo(px + 0.5, plot.y); ctx.lineTo(px + 0.5, plot.b);
  ctx.moveTo(plot.x, py + 0.5); ctx.lineTo(plot.r, py + 0.5);
  ctx.stroke(); ctx.setLineDash([]); ctx.globalAlpha = 1;
  const price = view.maxP - ((py - plot.y) / plot.h) * (view.maxP - view.minP);
  roundRect(ctx, plot.r + 2, py - 9, axisW - 4, 18, 4);
  ctx.fillStyle = C.grid2; ctx.fill(); ctx.fillStyle = C.text;
  ctx.textAlign = 'left'; ctx.font = '10px monospace';
  ctx.fillText(fmtP(price), plot.r + 7, py + 0.5);
  const hi = clamp(Math.floor(view.center - view.visible / 2 + (px - plot.x) / bw), 0, bars.length - 1);
  if (!bars[hi]) return;
  const tt = fmtT(bars[hi].t), tw = ctx.measureText(tt).width + 12;
  roundRect(ctx, clamp(px - tw / 2, plot.x, plot.r - tw), plot.b + 2, tw, 17, 4);
  ctx.fillStyle = C.grid2; ctx.fill(); ctx.fillStyle = C.text;
  ctx.textAlign = 'center';
  ctx.fillText(tt, clamp(px, plot.x + tw / 2, plot.r - tw / 2), plot.b + 11);
}

export function fitViewPrices(view, bars, playhead) {
  if (!bars || !bars.length) return;
  const f = Math.min(Math.floor(playhead), bars.length - 1);
  const left = view.center - view.visible / 2;
  const i0 = Math.max(0, Math.floor(left)), i1 = Math.min(f, bars.length - 1);
  let lo = Infinity, hi = -Infinity;
  for (let i = i0; i <= i1; i++) {
    if (bars[i]) { lo = Math.min(lo, bars[i].l); hi = Math.max(hi, bars[i].h); }
  }
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) return;
  const pad = (hi - lo) * 0.08 + (hi === lo ? 1 : 0.05);
  view.minP = lo - pad;
  view.maxP = hi + pad;
}

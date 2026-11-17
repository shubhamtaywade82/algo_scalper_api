export const SEEDS = [1337, 4242, 9001, 2718, 3141, 8080];
export const BASE_BIN = 0.05;
export const NORMAL = 220;
export const REF = NORMAL * 9;
export const SESSION_BARS = 240;
export const START_PLAY = 200;
export const MAX_BARS = 900;
export const TF_MS = { 1: 60e3, 5: 300e3, 15: 900e3, 60: 3600e3 };

export const SYMBOL_CONFIG = {
  NIFTY: { baseBin: 5, defaultBin: 10, roundStep: 50, exch: 'NSE INDEX' },
  BANKNIFTY: { baseBin: 10, defaultBin: 25, roundStep: 100, exch: 'NSE INDEX' },
  SENSEX: { baseBin: 20, defaultBin: 50, roundStep: 100, exch: 'BSE INDEX' },
  SIM_SOL: { baseBin: 0.05, defaultBin: 0.1, roundStep: 0.5, exch: 'BINANCE PERP' }
};

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;

// 32-bit deterministic PRNG ensures replay state is perfectly reproducible across reloads
export function mulberry32(seed) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = t + Math.imul(t ^ (t >>> 7), 61 | t) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function createSessionState(seed = SEEDS[0], tf = 5, symbol = 'NIFTY') {
  const cfg = SYMBOL_CONFIG[symbol] || SYMBOL_CONFIG.NIFTY;
  const startTime = Math.floor(Date.now() / TF_MS[tf]) * TF_MS[tf] - SESSION_BARS * TF_MS[tf];
  return {
    seed,
    tf,
    symbol,
    baseBin: cfg.baseBin,
    rng: mulberry32(seed),
    startTime,
    bars: [],
    snaps: [],
    bigsSnap: [],
    events: [],
    zones: [],
    book: new Map(),
    bigs: new Map(),
    playhead: START_PLAY,
    evCursor: 0,
    flashes: [],
    halted: false
  };
}

function getRegime(i, tf, lastPrice) {
  const scale = Math.sqrt(tf / 5);
  if (i < 55) return { drift: -0.048 * scale, vol: 0.09 * scale };
  if (i < 80) return { drift: 0.022 * scale, vol: 0.07 * scale };
  if (i < 125) return { drift: -0.012 * scale, vol: 0.06 * scale };
  if (i < 185) return { drift: 0.018 * scale, vol: 0.07 * scale };
  if (i < SESSION_BARS) return { drift: -0.008 * scale, vol: 0.055 * scale };
  return { drift: (72.4 - lastPrice) * 0.02 + Math.sin(i * 0.7) * 0.01, vol: 0.06 * scale };
}

function createBarPath(open, close, high, low, vol, rng) {
  const path = [];
  const peakHighIdx = 2 + Math.floor(rng() * 4);
  const peakLowIdx = 6 + Math.floor(rng() * 4);
  for (let k = 0; k < 12; k++) {
    let p = lerp(open, close, k / 11);
    if (k === peakHighIdx) p = high;
    else if (k === peakLowIdx) p = low;
    else if (k > 0 && k < 11) p += (rng() - 0.5) * vol * 0.5;
    path.push(clamp(p, low, high));
  }
  path[0] = open;
  path[11] = close;
  return path;
}

function createCandle(state, i) {
  const rng = state.rng;
  const prevClose = state.bars.length ? state.bars[state.bars.length - 1].c : 74.42;
  const { drift, vol } = getRegime(i, state.tf, prevClose);
  const open = prevClose;
  const close = open + drift + (rng() * 2 - 1) * vol + Math.sin(i * 0.35) * vol * 0.25;
  const high = Math.max(open, close) + rng() * vol * 0.9;
  const low = Math.min(open, close) - rng() * vol * 0.9;
  const volume = 9000 * (0.5 + rng() * 1.6) * (1 + (2 * Math.abs(close - open)) / vol);
  const buyR = clamp(0.5 + ((close - open) / (vol * 2)) * 0.4 + (rng() - 0.5) * 0.2, 0.1, 0.9);
  const path = createBarPath(open, close, high, low, vol, rng);
  return { t: state.startTime + i * TF_MS[state.tf], o: open, h: high, l: low, c: close, v: volume, buyR, path };
}

function spawnWallEvents(state, midPrice, i) {
  if (state.rng() >= 0.13) return;
  const side = state.rng() < 0.5 ? 'bid' : 'ask';
  const dist = 0.15 + state.rng() * 0.85;
  const bin = state.baseBin || BASE_BIN;
  const price = Math.round((midPrice + (side === 'bid' ? -dist : dist)) / bin) * bin;
  const idx = Math.round(price / bin);
  if (!state.bigs.has(idx)) {
    const size = NORMAL * (4 + state.rng() * 8);
    state.book.set(idx, size);
    state.bigs.set(idx, { born: i, side });
    state.events.push({ bar: i, type: 'wall', price: idx * bin, size, side });
  }
}

function evaluateBigWalls(state, bar, i) {
  const bin = state.baseBin || BASE_BIN;
  for (const [idx, meta] of [...state.bigs.entries()]) {
    const p = idx * bin;
    const size = state.book.get(idx) || 0;
    const touched = meta.side === 'ask' ? bar.h >= p : bar.l <= p;
    if (i - meta.born > 70 && !touched) {
      state.bigs.delete(idx);
      state.book.delete(idx);
      continue;
    }
    if (touched || Math.abs(p - bar.c) < bin * 3) {
      resolveWallTest(state, idx, p, size, meta.side, touched, i);
    }
  }
}

function resolveWallTest(state, idx, price, size, side, touched, i) {
  const r = state.rng();
  if (r < 0.45) {
    state.events.push({ bar: i, type: 'pull', price, size, side });
    state.bigs.delete(idx);
    state.book.delete(idx);
  } else if (touched) {
    if (r < 0.75) {
      const remaining = size * 0.45;
      state.events.push({ bar: i, type: 'held', price, size, side });
      if (remaining < NORMAL * 1.8) {
        state.bigs.delete(idx);
        state.book.delete(idx);
      } else state.book.set(idx, remaining);
    } else {
      state.events.push({ bar: i, type: 'brk', price, size, side });
      state.bigs.delete(idx);
      state.book.delete(idx);
    }
  }
}

function evolveOrderBook(state, bar, i) {
  const bin = state.baseBin || BASE_BIN;
  const mid = bar.c;
  const lo = Math.round((mid - bin * 50) / bin);
  const hi = Math.round((mid + bin * 50) / bin);
  for (const idx of [...state.book.keys()]) {
    const p = idx * bin;
    if (p < mid - bin * 60 || p > mid + bin * 60) {
      state.book.delete(idx);
      state.bigs.delete(idx);
    }
  }
  for (let idx = lo; idx <= hi; idx++) {
    const p = idx * bin;
    const round = Math.abs(p % (bin * 10)) < 0.001;
    if (!state.book.has(idx)) {
      if (state.rng() < 0.85) state.book.set(idx, NORMAL * (0.25 + state.rng() * 1.1) * (round ? 1.5 : 1));
    } else {
      let s = state.book.get(idx) * (0.86 + state.rng() * 0.28);
      if (!state.bigs.has(idx) && state.rng() < 0.015) s = 0;
      if (s > 2) state.book.set(idx, s);
      else state.book.delete(idx);
    }
  }
  spawnWallEvents(state, mid, i);
  evaluateBigWalls(state, bar, i);
  state.snaps[i] = [...state.book.entries()].filter((e) => e[1] > 2);
  state.bigsSnap[i] = [...state.bigs.entries()].map(([idx, m]) => ({
    idx,
    born: m.born,
    side: m.side,
    size: state.book.get(idx) || 0
  }));
}

function detectFvgs(state, bar, i) {
  const minGap = (state.baseBin || BASE_BIN) * 0.5;
  if (i >= 2) {
    const prev2 = state.bars[i - 2];
    if (bar.l - prev2.h > minGap) state.zones.push({ lo: prev2.h, hi: bar.l, start: i, side: 'bull', filled: null });
    if (prev2.l - bar.h > minGap) state.zones.push({ lo: bar.h, hi: prev2.l, start: i, side: 'bear', filled: null });
  }
  for (const z of state.zones) {
    if (z.filled === null && z.start < i) {
      if (z.side === 'bull' && bar.l <= z.lo) z.filled = i;
      if (z.side === 'bear' && bar.h >= z.hi) z.filled = i;
    }
  }
  if (state.zones.length > 80) state.zones.splice(0, state.zones.length - 80);
}

export function loadRealCandlesIntoSession(state, apiCandles, symbolKey = 'NIFTY') {
  if (!apiCandles || !apiCandles.length) return;
  const cfg = SYMBOL_CONFIG[symbolKey] || SYMBOL_CONFIG.NIFTY;
  state.symbol = symbolKey;
  state.baseBin = cfg.baseBin;
  state.bars = [];
  state.snaps = [];
  state.bigsSnap = [];
  state.events = [];
  state.zones = [];
  state.book = new Map();
  state.bigs = new Map();
  for (let i = 0; i < apiCandles.length; i++) {
    const c = apiCandles[i];
    const path = [];
    for (let k = 0; k < 12; k++) path.push(lerp(c.open, c.close, k / 11));
    path[3] = c.high;
    path[7] = c.low;
    const bar = { t: c.time * 1000, o: c.open, h: c.high, l: c.low, c: c.close, v: c.volume || 1000, buyR: c.close >= c.open ? 0.6 : 0.4, path };
    state.bars.push(bar);
    evolveOrderBook(state, bar, i);
    detectFvgs(state, bar, i);
  }
  state.playhead = Math.max(0, state.bars.length - 1);
  restoreEngineTo(state, Math.floor(state.playhead));
}

export function pushLiveTick(state, price) {
  if (!state.bars.length || !Number.isFinite(price) || price <= 0) return;
  const lastBar = state.bars[state.bars.length - 1];
  lastBar.c = price;
  lastBar.h = Math.max(lastBar.h, price);
  lastBar.l = Math.min(lastBar.l, price);
  if (lastBar.path && lastBar.path.length) lastBar.path[lastBar.path.length - 1] = price;
}

export function stepBar(state, i) {
  const bar = createCandle(state, i);
  evolveOrderBook(state, bar, i);
  detectFvgs(state, bar, i);
  state.bars.push(bar);
}

export function ensureBars(state, count) {
  const target = Math.min(count, MAX_BARS - 1);
  while (state.bars.length <= target) stepBar(state, state.bars.length);
}

export function restoreEngineTo(state, barIdx) {
  const f = clamp(barIdx, 0, state.bars.length - 1);
  state.book = new Map(state.snaps[f] || []);
  state.bigs = new Map((state.bigsSnap[f] || []).map((b) => [b.idx, { born: b.born, side: b.side }]));
  state.evCursor = 0;
  while (state.evCursor < state.events.length && state.events[state.evCursor].bar <= f) state.evCursor++;
}

export function getAggregatedBook(state, binSize, cache) {
  if (cache.bin === binSize && cache.len === state.bars.length && cache.symbol === state.symbol) return cache.data;
  const base = state.baseBin || BASE_BIN;
  const k = Math.max(1, Math.round(binSize / base));
  const data = [];
  for (let i = 0; i < state.bars.length; i++) {
    const m = new Map();
    for (const [idx, s] of state.snaps[i] || []) {
      const ai = Math.round(idx / k);
      m.set(ai, (m.get(ai) || 0) + s);
    }
    data[i] = m;
  }
  cache.data = data;
  cache.len = state.bars.length;
  cache.bin = binSize;
  cache.symbol = state.symbol;
  return data;
}

export function getFormingValues(state) {
  const i = Math.min(Math.floor(state.playhead), state.bars.length - 1);
  const b = state.bars[i];
  if (!b) return { i: 0, b: null, f: 0, cur: 0, h: 0, l: 0 };
  const f = clamp(state.playhead - i, 0, 1);
  const k = f * 11;
  const i0 = Math.floor(k);
  const i1 = Math.min(11, i0 + 1);
  const cur = lerp(b.path[i0], b.path[i1], k - i0);
  let h = b.o;
  let l = b.o;
  for (let j = 0; j <= i0; j++) {
    h = Math.max(h, b.path[j]);
    l = Math.min(l, b.path[j]);
  }
  return { i, b, f, cur, h: Math.max(h, cur), l: Math.min(l, cur) };
}

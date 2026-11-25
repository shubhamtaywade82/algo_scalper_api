import { detectFVGs, detectLiquidityPools, detectOrderBlocks } from '../smc/smcEngine';

export const SEEDS = [1337, 4242, 9001, 2718, 3141, 8080];
export const BASE_BIN = 0.05;
export const NORMAL = 220;
export const REF = NORMAL * 9;
export const SESSION_BARS = 240;
export const START_PLAY = 200;
export const MAX_BARS = 900;
export const TF_MS = { 1: 60e3, 5: 300e3, 15: 900e3, 25: 1500e3, 60: 3600e3 };

export const SYMBOL_CONFIG = {
  NIFTY: { baseBin: 5, defaultBin: 10, roundStep: 50, exch: 'NSE INDEX' },
  BANKNIFTY: { baseBin: 10, defaultBin: 25, roundStep: 100, exch: 'NSE INDEX' },
  SENSEX: { baseBin: 20, defaultBin: 50, roundStep: 100, exch: 'BSE INDEX' },
  SIM_SOL: { baseBin: 0.05, defaultBin: 0.1, roundStep: 0.5, exch: 'BINANCE PERP' }
};

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;

export function createSessionState(seed = SEEDS[0], tf = 5, symbol = 'NIFTY') {
  const cfg = SYMBOL_CONFIG[symbol] || SYMBOL_CONFIG.NIFTY;
  const tfMs = TF_MS[tf] || 300e3;
  const startTime = Math.floor(Date.now() / tfMs) * tfMs - SESSION_BARS * tfMs;
  return {
    seed,
    tf,
    symbol,
    baseBin: cfg.baseBin,
    startTime,
    bars: [],
    events: [],
    zones: [],
    pools: [],
    orderBlocks: [],
    liveDepth: null,
    playhead: 0,
    halted: false
  };
}

export function loadRealCandlesIntoSession(state, apiCandles, symbolKey = 'NIFTY') {
  if (!apiCandles || !apiCandles.length) return;
  const cfg = SYMBOL_CONFIG[symbolKey] || SYMBOL_CONFIG.NIFTY;
  state.symbol = symbolKey;
  state.baseBin = cfg.baseBin;
  state.bars = [];
  state.zones = [];
  state.pools = [];
  state.orderBlocks = [];

  for (let i = 0; i < apiCandles.length; i++) {
    const c = apiCandles[i];
    const path = [];
    for (let k = 0; k < 12; k++) path.push(lerp(c.open, c.close, k / 11));
    path[3] = c.high;
    path[7] = c.low;
    const bar = {
      t: c.time * 1000,
      o: c.open,
      h: c.high,
      l: c.low,
      c: c.close,
      v: c.volume || 1000,
      buyR: c.close >= c.open ? 0.6 : 0.4,
      path
    };
    state.bars.push(bar);
  }

  // Detect real structural FVGs on actual market candles
  const realFvgs = detectFVGs(apiCandles);
  state.zones = realFvgs.map((f) => ({
    lo: f.bottom,
    hi: f.top,
    startTime: f.startTime * 1000,
    endTime: f.endTime ? f.endTime * 1000 : null,
    side: f.type === 'BULLISH' ? 'bull' : 'bear',
    filled: f.mitigated
  }));

  // Detect real swing liquidity pools on actual market candles
  const realPools = detectLiquidityPools(apiCandles);
  state.pools = realPools.map((p) => ({
    level: p.level,
    type: p.type,
    startTime: p.startTime * 1000,
    swept: p.status === 'SWEPT'
  }));

  // Detect structural Order Blocks on actual market candles
  const realObs = detectOrderBlocks(apiCandles);
  state.orderBlocks = realObs.map((ob) => ({
    lo: ob.bottom,
    hi: ob.top,
    startTime: ob.startTime * 1000,
    side: ob.type === 'BULLISH' ? 'bull' : 'bear'
  }));

  state.playhead = Math.max(0, state.bars.length - 1);
}

export function applyLiveDepth(state, depthData) {
  if (!depthData) return;
  state.liveDepth = depthData;
  const f = Math.floor(state.playhead);
  const bids = depthData.bid || [];
  const asks = depthData.ask || [];
  if (bids.length && bids[0].qty > 200) {
    state.events.push({ bar: f, type: 'wall', price: bids[0].price, size: bids[0].qty, side: 'bid', time: Date.now() });
  }
  if (asks.length && asks[0].qty > 200) {
    state.events.push({ bar: f, type: 'wall', price: asks[0].price, size: asks[0].qty, side: 'ask', time: Date.now() });
  }
  if (state.events.length > 40) state.events.splice(0, state.events.length - 40);
}

export function pushLiveTick(state, price) {
  if (!state.bars.length || !Number.isFinite(price) || price <= 0) return;
  const lastBar = state.bars[state.bars.length - 1];
  lastBar.c = price;
  lastBar.h = Math.max(lastBar.h, price);
  lastBar.l = Math.min(lastBar.l, price);
  if (lastBar.path && lastBar.path.length) lastBar.path[lastBar.path.length - 1] = price;
}

export function getAggregatedBook(state, binSize, cache) {
  if (cache.bin === binSize && cache.len === state.bars.length && cache.symbol === state.symbol) return cache.data;
  const data = [];
  let maxV = 1;
  for (let i = 0; i < state.bars.length; i++) {
    if (state.bars[i].v > maxV) maxV = state.bars[i].v;
  }
  for (let i = 0; i < state.bars.length; i++) {
    const bar = state.bars[i];
    const m = new Map();
    const lo = Math.floor(bar.l / binSize) * binSize;
    const hi = Math.ceil(bar.h / binSize) * binSize;
    const steps = Math.max(1, Math.round((hi - lo) / binSize));
    const volPerBin = (bar.v / maxV) * NORMAL * 3;
    for (let p = lo; p <= hi; p += binSize) {
      m.set(Math.round(p / binSize), volPerBin);
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

export function isCandleBoundary(intervalStr, date) {
  const ival = parseInt(intervalStr, 10) || 5;
  if (ival === 1) return true;
  if (ival === 5 || ival === 15) return date.getMinutes() % ival === 0;
  if (ival === 60) return date.getMinutes() === 15;
  const istMins = ((date.getTime() + (date.getTimezoneOffset() + 330) * 60000) / 60000) % 1440 - (9 * 60 + 15);
  return istMins < 0 || istMins % ival === 0;
}

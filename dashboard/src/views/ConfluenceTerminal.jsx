import { createSignal, createMemo, createEffect, onMount, onCleanup, For, Show } from 'solid-js';
import { A, useSearchParams } from '@solidjs/router';
import { dashboardApiHeaders } from '../lib/dashboardApi';
import { useDashboard } from '../stores/useDashboard';
import { usePositions } from '../stores/usePositions';
import { useOptionChain } from '../stores/useOptionChain';
import { useAgent } from '../stores/useAgent';
import { deriveOptionsView, optionLevels } from '../lib/confluence/optionsMetrics';
import {
  SYMBOL_CONFIG, TF_MS, clamp, createSessionState, getAggregatedBook,
  getFormingValues, loadRealCandlesIntoSession, pushLiveTick, isCandleBoundary
} from '../lib/confluence/engine';
import { createAudioEngine } from '../lib/confluence/audio';
import {
  C, fmtP, fmtT, fmtD, fmtCountdown, buildLUT, getY,
  drawGrid, drawHeatmap, drawFvgAndRays, drawCandlesAndVolume, drawLastPriceLine,
  drawChips, drawDepthProfile, drawCrosshair, fitViewPrices, drawKeyLevels, drawOptionLevels
} from '../lib/confluence/renderer';
import { createGestures, followCenter, hitZone } from '../lib/confluence/interaction';
import TerminalSidebar from '../components/charts/TerminalSidebar';

const SYMBOLS = ['NIFTY', 'BANKNIFTY', 'SENSEX'];
const TIMEFRAMES = [{ id: '1', lbl: '1m' }, { id: '5', lbl: '5m' }, { id: '15', lbl: '15m' }, { id: '25', lbl: '25m' }, { id: '60', lbl: '1h' }];
const LAYERS = [['heat', 'VOLMAP'], ['fvg', 'FVG'], ['ob', 'OB'], ['vol', 'VOL'], ['sr', 'S/R'], ['opt', 'OPTIONS']];
const DEPTH_POLL_MS = 4000;
const DEPTH_TIMEOUT_MS = 30000;
const AXIS_W = 64;
const EMPTY_DEPTH = { bid: [], ask: [], totalBid: 0, totalAsk: 0, bidPct: 50, spread: '--', at: 0, error: false };
const EMPTY_SPOT = { price: 0, base: 0, change: 0, pct: 0, up: true, dayHigh: 0, dayLow: 0 };

export default function ConfluenceTerminal() {
  let wrapRef, sceneRef, overRef, depthTimer = null, boundaryTimer = null, loadTicket = 0, disposed = false;
  const audio = createAudioEngine(), [searchParams] = useSearchParams();
  const initSym = (searchParams.symbol || localStorage.getItem('smc_symbol') || 'NIFTY').toUpperCase();
  const [symbol, setSymbol] = createSignal(SYMBOLS.includes(initSym) ? initSym : 'NIFTY');
  const [tf, setTf] = createSignal(searchParams.tf || localStorage.getItem('smc_interval') || '5');
  const [playing, setPlaying] = createSignal(false), [halted, setHalted] = createSignal(false), [speed, setSpeed] = createSignal(1);
  const [palette, setPalette] = createSignal(localStorage.getItem('smc_palette') || 'ion'), [candleStyle, setCandleStyle] = createSignal('hollow');
  const [layers, setLayers] = createSignal({ heat: false, fvg: true, ob: true, vol: true, sr: true, opt: true });
  const [spot, setSpot] = createSignal(EMPTY_SPOT), [depth, setDepth] = createSignal(EMPTY_DEPTH);
  const [loading, setLoading] = createSignal(false), [loadError, setLoadError] = createSignal(null), [barCount, setBarCount] = createSignal(0);
  const [formingBar, setFormingBar] = createSignal(null), [hoverBar, setHoverBar] = createSignal(null), [following, setFollowing] = createSignal(true), [autoScale, setAutoScale] = createSignal(true), [mobileSidebarOpen, setMobileSidebarOpen] = createSignal(false);
  const { indices, optionsBuying, connected, system, marketStatus } = useDashboard();
  const { open: openPositions, closeOpenPosition, closingPositionId } = usePositions();
  const buyingState = createMemo(() => (optionsBuying() ? optionsBuying()[symbol().toLowerCase()] : null));
  const chartPositions = createMemo(() => (openPositions() || []).filter((p) => (p.index_key || '').toUpperCase() === symbol().toUpperCase()));
  const { chain } = useOptionChain(symbol);
  const { status: agentStatus } = useAgent();
  const optionsView = createMemo(() => deriveOptionsView(chain()));
  const chartLevels = createMemo(() => (layers().opt ? optionLevels(optionsView()) : []));
  const isLive = createMemo(() => marketStatus() === 'open' && connected() && system()?.ws_market_feed !== false);
  let state = createSessionState(1337, tf(), symbol()), aggCache = { bin: 10, sig: '', data: [], symbol: symbol() }, lut = buildLUT(palette());
  let view = { center: 50, visible: 70, minP: 24000, maxP: 26000 }, plot = { x: 8, y: 8, w: 800, h: 500, r: 808, b: 508 };
  let dirty = true, dpr = Math.min(2, window.devicePixelRatio || 1), hover = null, hoverIdx = -1, animId = null, prevT = performance.now();

  function resize() {
    if (!wrapRef || !sceneRef || !overRef) return;
    const r = wrapRef.getBoundingClientRect(), w = Math.max(80, r.width), h = Math.max(80, r.height), axis = w < 560 ? 56 : 72;
    for (const cv of [sceneRef, overRef]) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    plot = { x: 8, y: 8, w: w - axis - 12, h: h - 40, r: w - axis - 4, b: h - 32 };
    dirty = true;
  }

  async function fetchDepthData(sym) {
    try {
      const res = await fetch(`/api/depth?symbol=${sym}`, { headers: dashboardApiHeaders(), signal: AbortSignal.timeout(DEPTH_TIMEOUT_MS) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (sym !== symbol()) return;
      const bid = data.bid || [], ask = data.ask || [], total = (data.totalBidQty || 0) + (data.totalAskQty || 0) || 1;
      const spread = ask[0] && bid[0] ? (ask[0].price - bid[0].price).toFixed(2) : '--';
      setDepth({ bid, ask, totalBid: data.totalBidQty || 0, totalAsk: data.totalAskQty || 0, bidPct: ((data.totalBidQty || 0) / total) * 100, spread, at: Date.now(), error: false });
    } catch {
      setDepth((d) => ({ ...d, error: true }));
    }
  }

  // Single-flight: the next poll is scheduled only after the previous one settles, so a slow upstream can't pile up requests.
  async function pollDepth() {
    if (!document.hidden) await fetchDepthData(symbol());
    if (!disposed) depthTimer = setTimeout(pollDepth, DEPTH_POLL_MS);
  }

  async function loadData(sym, intervalStr, { silent = false } = {}) {
    const ticket = ++loadTicket, switched = state.symbol !== sym || String(state.tf) !== String(intervalStr);
    if (!silent) { setLoading(true); setLoadError(null); }
    state.tf = intervalStr;
    try {
      const res = await fetch(`/api/candles/${sym}?interval=${intervalStr}&days=5`, { headers: dashboardApiHeaders() });
      if (!res.ok) throw new Error(`candles request failed (HTTP ${res.status})`);
      const data = await res.json();
      if (ticket !== loadTicket) return;
      if (!data.candles?.length) throw new Error('no candles returned for this session');
      loadRealCandlesIntoSession(state, data.candles, sym);
      setBarCount(state.bars.length); setLoadError(null);
      applyLiveTick(); fitViewPrices(view, state.bars, state.playhead); updateStats();
    } catch (e) {
      if (ticket !== loadTicket) return;
      if (switched) { state.bars = []; setBarCount(0); }
      setLoadError(e.message);
    } finally {
      if (ticket === loadTicket) { setLoading(false); dirty = true; }
    }
  }

  function updateStats() {
    const fv = getFormingValues(state);
    if (!fv.b) return;
    const lastDay = fmtD(fv.b.t);
    let first = fv.i;
    while (first > 0 && fmtD(state.bars[first - 1].t) === lastDay) first--;
    let dayHigh = -Infinity, dayLow = Infinity;
    for (let i = first; i <= fv.i; i++) { dayHigh = Math.max(dayHigh, state.bars[i].h); dayLow = Math.min(dayLow, state.bars[i].l); }
    const reported = Number(indices()?.[`${symbol().toLowerCase()}_prev_close`]);
    const base = reported > 0 ? reported : first > 0 ? state.bars[first - 1].c : state.bars[first].o;
    const change = fv.cur - base;
    setSpot({ price: fv.cur, base, change, pct: (change / base) * 100, up: change >= 0, dayHigh, dayLow });
    setFormingBar({ ...state.bars[state.bars.length - 1] });
  }

  function applyLiveTick() {
    const price = Number(indices()?.[symbol().toLowerCase()]);
    const result = pushLiveTick(state, price);
    if (result === 'reload') loadData(symbol(), tf(), { silent: true });
    else if (result) { if (result === 'rolled') setBarCount(state.bars.length); updateStats(); dirty = true; }
  }

  function scheduleNextMinuteFetch() {
    const now = new Date(), msUntilNext = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
    boundaryTimer = setTimeout(() => {
      if (!disposed && isCandleBoundary(tf(), new Date())) loadData(symbol(), tf(), { silent: true });
      scheduleNextMinuteFetch();
    }, msUntilNext + 2000);
  }

  function switchMarket(nextSymbol, nextTf) {
    setSymbol(nextSymbol); setTf(nextTf); setDepth(EMPTY_DEPTH); setFollowing(true); setAutoScale(true);
    loadData(nextSymbol, nextTf); fetchDepthData(nextSymbol);
  }

  const goLive = () => { setPlaying(false); state.playhead = Math.max(0, state.bars.length - 1); setFollowing(true); updateStats(); dirty = true; };
  const togglePlay = () => {
    if (!playing() && state.playhead >= state.bars.length - 1) state.playhead = Math.max(1, state.bars.length - 80);
    setPlaying(!playing()); audio.ui();
  };

  createEffect(() => {
    localStorage.setItem('smc_symbol', symbol());
    localStorage.setItem('smc_interval', tf());
    localStorage.setItem('smc_palette', palette());
  });

  createEffect(() => { indices(); if (!playing()) applyLiveTick(); });
  createEffect(() => { chartLevels(); dirty = true; });

  function animate(now) {
    const dt = Math.min(50, now - prevT); prevT = now;
    if (playing() && !halted()) {
      state.playhead += dt / (1600 / speed());
      if (state.playhead >= state.bars.length - 1) goLive();
      else { updateStats(); dirty = true; }
    }
    if (following()) {
      const target = followCenter(view, playing() ? state.playhead + 1 : state.bars.length);
      if (view.center !== target) { view.center = target; dirty = true; }
    }
    if (state.bars.length) { if (autoScale()) fitViewPrices(view, state.bars, state.playhead); renderFrame(); }
    else clearCanvases();
    animId = requestAnimationFrame(animate);
  }

  function clearCanvases() {
    for (const cv of [sceneRef, overRef]) cv?.getContext('2d').clearRect(0, 0, cv.width, cv.height);
  }

  function renderFrame() {
    if (!sceneRef || !overRef) return;
    const sc = sceneRef.getContext('2d'), oc = overRef.getContext('2d'), bw = plot.w / view.visible;
    const cfg = SYMBOL_CONFIG[symbol()] || SYMBOL_CONFIG.NIFTY, aggData = getAggregatedBook(state, cfg.defaultBin, aggCache);
    if (dirty) {
      sc.setTransform(dpr, 0, 0, dpr, 0, 0); sc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
      drawGrid(sc, view, plot, state.bars, dpr, bw, AXIS_W);
      drawHeatmap(sc, view, plot, state, { heat: layers().heat, bin: cfg.defaultBin, gamma: 0.8 }, aggData, lut, bw);
      drawFvgAndRays(sc, view, plot, state, layers());
      if (layers().sr) drawKeyLevels(sc, view, plot, { levels: buyingState() });
      drawOptionLevels(sc, view, plot, chartLevels());
      drawCandlesAndVolume(sc, view, plot, state, { vol: layers().vol, candle: candleStyle() }, 0, state.bars.length - 1, bw);
      dirty = false;
    }
    oc.setTransform(dpr, 0, 0, dpr, 0, 0); oc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
    renderOverlay(oc, bw, aggData, cfg);
  }

  function levelChips(fv) {
    const priceY = getY(fv.cur, view, plot), up = fv.cur >= (fv.b?.o || 0);
    const chips = [{ y0: priceY, h: 16, bg: up ? C.bid : C.ask, fg: '#04070F', txt: fmtP(fv.cur) }];
    const barEnd = fv.b.t + (TF_MS[state.tf] || 300e3), remaining = barEnd - Date.now();
    if (!playing() && remaining > 0 && remaining <= (TF_MS[state.tf] || 300e3)) chips.push({ y0: priceY + 17, h: 14, bg: C.surface2, fg: C.muted, txt: fmtCountdown(remaining) });
    const bs = layers().sr ? buyingState() : null;
    if (bs?.support) chips.push({ y0: getY(bs.support, view, plot), h: 15, bg: '#10B981', fg: '#04070F', txt: `S ${bs.support.toFixed(0)}` });
    if (bs?.resistance) chips.push({ y0: getY(bs.resistance, view, plot), h: 15, bg: '#FF4D6D', fg: '#04070F', txt: `R ${bs.resistance.toFixed(0)}` });
    for (const lv of chartLevels()) {
      const y0 = getY(lv.price, view, plot);
      if (y0 > plot.y && y0 < plot.b) chips.push({ y0, h: 14, bg: lv.color, fg: '#04070F', txt: lv.label });
    }
    return chips;
  }

  function renderOverlay(oc, bw, aggData, cfg) {
    const fv = getFormingValues(state);
    if (!fv.b) return;
    if (layers().heat) drawDepthProfile(oc, plot, view, aggData[Math.floor(state.playhead)] || new Map(), fv.cur, cfg.defaultBin, 90);
    drawLastPriceLine(oc, plot, getY(fv.cur, view, plot), fv.cur >= fv.b.o ? C.bid : C.ask);
    drawChips(oc, plot, AXIS_W, levelChips(fv));
    if (hover && !gestures.isDragging()) drawCrosshair(oc, hover, plot, view, AXIS_W, state.bars, bw);
  }

  function setHover(point) {
    hover = point ? { px: point.x, py: point.y } : null;
    const idx = point ? clamp(Math.floor(view.center - view.visible / 2 + (point.x - plot.x) / (plot.w / view.visible)), 0, state.bars.length - 1) : -1;
    if (idx !== hoverIdx) { hoverIdx = idx; setHoverBar(state.bars[idx] ? { ...state.bars[idx] } : null); }
  }

  function onDoubleClick(e) {
    const r = wrapRef.getBoundingClientRect(), zone = hitZone(e.clientX - r.left, e.clientY - r.top, plot);
    if (zone === 'priceAxis') { setAutoScale(true); dirty = true; }
    else if (zone === 'timeAxis') resetView();
  }

  const resetView = () => { setAutoScale(true); view.visible = 70; goLive(); };
  const gestures = createGestures({
    view: () => view, plot: () => plot, barCount: () => state.bars.length, following, setFollowing, autoScale, setAutoScale,
    markDirty: () => { dirty = true; }, setHover, setCursor: (c) => { if (wrapRef) wrapRef.style.cursor = c; }, goLive, resetView
  });

  onMount(() => {
    resize(); loadData(symbol(), tf()); window.addEventListener('resize', resize);
    animId = requestAnimationFrame(animate); pollDepth(); scheduleNextMinuteFetch();
    window.addEventListener('keydown', gestures.onKeyDown);
  });
  onCleanup(() => {
    disposed = true;
    window.removeEventListener('resize', resize); window.removeEventListener('keydown', gestures.onKeyDown);
    if (animId) cancelAnimationFrame(animId);
    clearTimeout(depthTimer); clearTimeout(boundaryTimer);
  });
  const toggleLayer = (k) => { setLayers((l) => ({ ...l, [k]: !l[k] })); dirty = true; };
  const shownBar = () => hoverBar() || formingBar();
  const btn = 'px-2.5 py-1 rounded text-[11px] font-bold transition-colors';

  return (
    <div class="h-screen w-screen bg-[#04070F] text-[#E9EFFA] flex flex-col font-mono select-none overflow-hidden">
      <header class="h-14 border-b border-[#182742] bg-[#070D1A]/90 px-4 flex items-center justify-between z-20 backdrop-blur gap-4">
        <div class="flex items-center gap-3 min-w-0">
          <A href="/" class="text-xs text-[#8CA0BF] hover:text-[#3FC1FF] transition font-bold">← DASHBOARD</A>
          <div class="h-4 w-px bg-[#24375E]" />
          <div class="flex bg-[#070D1A] rounded p-0.5 border border-[#182742]">
            <For each={SYMBOLS}>{(s) => (
              <button onClick={() => switchMarket(s, tf())} class={`${btn} ${symbol() === s ? 'bg-[#152441] text-[#3FC1FF]' : 'text-[#8CA0BF] hover:text-white'}`}>{s}</button>
            )}</For>
          </div>
          <div class="flex bg-[#070D1A] rounded p-0.5 border border-[#182742]">
            <For each={TIMEFRAMES}>{(t) => (
              <button onClick={() => switchMarket(symbol(), t.id)} class={`${btn} ${tf() === t.id ? 'bg-[#152441] text-[#3FC1FF]' : 'text-[#8CA0BF] hover:text-white'}`}>{t.lbl}</button>
            )}</For>
          </div>
          <Show when={loading()}><span class="text-[10px] text-[#3FC1FF] animate-pulse">SYNCING…</span></Show>
        </div>
        <div class="flex items-center gap-4 text-xs">
          <Show when={spot().price > 0}>
            <div class="flex items-baseline gap-2 tabular-nums">
              <span class={`text-lg font-black ${spot().up ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}`}>{fmtP(spot().price)}</span>
              <span class={`font-bold ${spot().up ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}`}>{spot().up ? '+' : ''}{spot().change.toFixed(2)} ({spot().up ? '+' : ''}{spot().pct.toFixed(2)}%)</span>
            </div>
          </Show>
          <span class={`flex items-center gap-1.5 text-[10px] font-bold px-2 py-1 rounded border ${isLive() ? 'border-[#19E3B1]/40 text-[#19E3B1]' : 'border-[#FFB224]/40 text-[#FFB224]'}`}>
            <span class={`w-1.5 h-1.5 rounded-full ${isLive() ? 'bg-[#19E3B1] animate-pulse' : 'bg-[#FFB224]'}`} />{isLive() ? 'LIVE' : marketStatus() === 'open' ? 'FEED DOWN' : 'MARKET CLOSED'}
          </span>
          <button onClick={() => audio.setMuted(audio.isSoundOn())} class="px-2.5 py-1 rounded border border-[#24375E] bg-[#101C30] text-[10px]">{audio.isSoundOn() ? '🔊 SOUND' : '🔇 MUTED'}</button>
          <button onClick={() => { setHalted(!halted()); audio.kill(); }} title="Pauses chart replay and alert sounds only — does not touch trading"
            class={`px-2.5 py-1 rounded border text-[10px] font-bold ${halted() ? 'border-[#19E3B1] text-[#19E3B1]' : 'border-[#FFB224] text-[#FFB224]'}`}>{halted() ? '⏻ RESUME REPLAY' : '⏻ HALT REPLAY'}</button>
          <button onClick={() => setMobileSidebarOpen(!mobileSidebarOpen())}
            class="md:hidden px-2.5 py-1 rounded border border-[#3FC1FF]/50 bg-[#101C30] text-[10px] font-bold text-[#3FC1FF] hover:bg-[#3FC1FF]/10">
            📊 {mobileSidebarOpen() ? 'CLOSE' : 'PANEL'}
          </button>
        </div>
      </header>

      <div class="flex-1 flex min-h-0 relative">
        <div ref={wrapRef} class="flex-1 relative overflow-hidden touch-none bg-gradient-to-b from-[#070D1A] to-[#04070F]"
          onPointerDown={(e) => { audio.init(); audio.resume(); gestures.onPointerDown(e); }}
          onPointerMove={gestures.onPointerMove} onPointerUp={gestures.onPointerEnd} onPointerCancel={gestures.onPointerEnd}
          onPointerLeave={() => { if (!gestures.isDragging()) setHover(null); }}
          onDblClick={onDoubleClick}
          onWheel={gestures.onWheel}>
          <canvas ref={sceneRef} class="absolute inset-0 pointer-events-none" />
          <canvas ref={overRef} class="absolute inset-0" />

          <Show when={shownBar()}>
            <div class="absolute top-2 left-3 z-10 flex items-center gap-3 text-[11px] tabular-nums pointer-events-none">
              <span class="font-black text-white">{symbol()} · {TIMEFRAMES.find((t) => t.id === String(tf()))?.lbl}</span>
              <span class="text-[#8CA0BF]">{fmtD(shownBar().t)} {fmtT(shownBar().t)}</span>
              <span class="text-[#8CA0BF]">O <b class="text-[#E9EFFA]">{fmtP(shownBar().o)}</b></span>
              <span class="text-[#8CA0BF]">H <b class="text-[#19E3B1]">{fmtP(shownBar().h)}</b></span>
              <span class="text-[#8CA0BF]">L <b class="text-[#FF4D6D]">{fmtP(shownBar().l)}</b></span>
              <span class="text-[#8CA0BF]">C <b class={shownBar().c >= shownBar().o ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{fmtP(shownBar().c)}</b></span>
            </div>
          </Show>

          <Show when={barCount() === 0}>
            <div class="absolute inset-0 flex flex-col items-center justify-center gap-3 z-10 text-center px-6">
              <Show when={loadError()} fallback={<span class="text-xs text-[#3FC1FF] animate-pulse tracking-widest">LOADING {symbol()} CANDLES…</span>}>
                <span class="text-xs text-[#FFB224] font-bold">Could not load {symbol()} candles</span>
                <span class="text-[11px] text-[#8CA0BF] max-w-sm">{loadError()}</span>
                <button onClick={() => loadData(symbol(), tf())} class="px-3 py-1.5 rounded border border-[#3FC1FF]/50 text-[#3FC1FF] text-[11px] font-bold hover:bg-[#3FC1FF]/10">RETRY</button>
              </Show>
            </div>
          </Show>

          <Show when={barCount() > 0}>
            <div class="absolute bottom-9 right-20 z-10 flex gap-2 text-[10px] font-bold">
              <Show when={!following()}>
                <button onClick={goLive} class="px-3 py-1.5 rounded-full bg-[#3FC1FF]/20 border border-[#3FC1FF]/50 text-[#3FC1FF] hover:bg-[#3FC1FF]/30">⇥ LATEST</button>
              </Show>
              <button onClick={() => { setAutoScale(!autoScale()); dirty = true; }} title="Auto-fit price scale to visible bars (drag the chart vertically or the price axis to turn off)"
                class={`px-2.5 py-1.5 rounded-full border ${autoScale() ? 'border-[#3FC1FF]/50 text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF] bg-[#101C30]'}`}>AUTO</button>
              <button onClick={resetView} title="Reset zoom and scroll to latest (Alt+R)" class="px-2.5 py-1.5 rounded-full border border-[#24375E] text-[#8CA0BF] bg-[#101C30] hover:text-white">RESET</button>
            </div>
          </Show>
        </div>

        <TerminalSidebar symbol={symbol()} spot={spot()} bar={shownBar()} hovering={!!hoverBar()} buyingState={buyingState()}
          options={optionsView()} agentStatus={agentStatus()} positions={chartPositions()} onExit={closeOpenPosition} closingId={closingPositionId()} depth={depth()}
          mobileOpen={mobileSidebarOpen()} onClose={() => setMobileSidebarOpen(false)} />
      </div>

      <footer class="h-14 border-t border-[#182742] bg-[#070D1A]/95 px-4 flex items-center justify-between text-xs z-20">
        <div class="flex items-center gap-3">
          <button onClick={togglePlay} class="px-3 py-1.5 rounded bg-[#8F7BFF]/20 border border-[#8F7BFF]/50 text-[#8F7BFF] font-bold">{playing() ? '❚❚ PAUSE' : '▶ REPLAY'}</button>
          <select value={speed()} onChange={(e) => setSpeed(Number(e.target.value))} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[11px]">
            <option value="0.5">0.5×</option><option value="1">1.0×</option><option value="2">2.0×</option><option value="4">4.0×</option>
          </select>
          <input type="range" min="1" max={Math.max(10, barCount() - 1)} value={Math.floor(state.playhead)}
            onInput={(e) => { state.playhead = Number(e.target.value); updateStats(); dirty = true; }} class="w-28 accent-[#3FC1FF]" />
        </div>
        <div class="flex items-center gap-1.5 overflow-x-auto">
          <For each={LAYERS}>{([key, label]) => (
            <button onClick={() => toggleLayer(key)} class={`px-2 py-1 rounded border text-[10px] ${layers()[key] ? 'border-[#3FC1FF] text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF]'}`}>{label}</button>
          )}</For>
          <button onClick={() => { setCandleStyle((s) => (s === 'hollow' ? 'solid' : 'hollow')); dirty = true; }} class="px-2 py-1 rounded border border-[#24375E] text-[#8CA0BF] text-[10px]">{candleStyle().toUpperCase()}</button>
          <select value={palette()} onChange={(e) => { setPalette(e.target.value); lut = buildLUT(e.target.value); dirty = true; }} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[10px]">
            <option value="ion">Ion Heat</option><option value="classic">Classic</option><option value="ultra">Ultraviolet</option>
          </select>
        </div>
      </footer>
    </div>
  );
}

import { createSignal, createMemo, createEffect, onMount, onCleanup, For, Show } from 'solid-js';
import { A, useSearchParams } from '@solidjs/router';
import { dashboardApiHeaders } from '../lib/dashboardApi';
import { useDashboard } from '../stores/useDashboard';
import { usePositions } from '../stores/usePositions';
import {
  SYMBOL_CONFIG, clamp, createSessionState, getAggregatedBook,
  getFormingValues, loadRealCandlesIntoSession, pushLiveTick, applyLiveDepth, isCandleBoundary
} from '../lib/confluence/engine';
import { createAudioEngine } from '../lib/confluence/audio';
import {
  C, fmtP, fmtS, fmtT, buildLUT, getY,
  drawGrid, drawHeatmap, drawFvgAndRays, drawCandlesAndVolume,
  drawChips, drawDepthProfile, drawCrosshair, fitViewPrices,
  drawKeyLevelsAndPositions
} from '../lib/confluence/renderer';

const SYMBOLS = ['NIFTY', 'BANKNIFTY', 'SENSEX'];
const TIMEFRAMES = [{ id: '1', lbl: '1m' }, { id: '5', lbl: '5m' }, { id: '15', lbl: '15m' }, { id: '25', lbl: '25m' }, { id: '60', lbl: '1h' }];
const LAYER_KEYS = ['heat', 'fvg', 'ob', 'vol', 'sr', 'pos', 'hud'];

export default function ConfluenceTerminal() {
  let wrapRef, sceneRef, overRef, pollTimer = null, boundaryTimer = null;
  const audio = createAudioEngine(), [searchParams] = useSearchParams();
  const initSym = (searchParams.symbol || localStorage.getItem('smc_symbol') || localStorage.getItem('chart_symbol') || 'NIFTY').toUpperCase();
  const [symbol, setSymbol] = createSignal(initSym), [tf, setTf] = createSignal(searchParams.tf || localStorage.getItem('smc_interval') || '5');
  const [playing, setPlaying] = createSignal(false), [halted, setHalted] = createSignal(false), [speed, setSpeed] = createSignal(1);
  const [palette, setPalette] = createSignal(localStorage.getItem('smc_palette') || 'ion'), [candleStyle, setCandleStyle] = createSignal('hollow');
  const [layers, setLayers] = createSignal({ heat: true, fvg: true, ob: true, vol: true, sr: true, pos: true, hud: true });
  const [spot, setSpot] = createSignal({ price: '--', delta: '0.00%', up: true, bids: '0', asks: '0', bidPct: 50, spread: '--' });
  const [levels, setLevels] = createSignal([]), [tape, setTape] = createSignal([]), [loading, setLoading] = createSignal(false);
  const { indices, optionsBuying } = useDashboard();
  const { open: openPositions, closeOpenPosition, closingPositionId } = usePositions();
  const buyingState = createMemo(() => (optionsBuying() ? optionsBuying()[symbol().toLowerCase()] : null));
  const chartPositions = createMemo(() => (openPositions() || []).filter(p => (p.index_key || '').toUpperCase() === symbol().toUpperCase()));
  let state = createSessionState(1337, 5, symbol()), aggCache = { bin: 10, len: 0, data: [], symbol: symbol() }, lut = buildLUT(palette());
  let view = { center: 50, visible: 70, minP: 24000, maxP: 26000 }, plot = { x: 8, y: 8, w: 800, h: 500, r: 808, b: 508 };
  let dirty = true, dpr = Math.min(2, window.devicePixelRatio || 1), hover = null, drag = null, animId = null, prevT = performance.now();

  function resize() {
    if (!wrapRef || !sceneRef || !overRef) return;
    const r = wrapRef.getBoundingClientRect(), w = Math.max(80, r.width), h = Math.max(80, r.height);
    for (const cv of [sceneRef, overRef]) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    plot = { x: 8, y: 8, w: w - (w < 560 ? 56 : 72) - 12, h: h - 40, r: w - (w < 560 ? 56 : 72) - 4, b: h - 32 };
    dirty = true;
  }

  async function fetchDepthData(sym) {
    try {
      const res = await fetch(`/api/depth?symbol=${sym}`, { headers: dashboardApiHeaders() });
      if (!res.ok) return;
      const data = await res.json();
      applyLiveDepth(state, data);
      const bids = data.bid || [], asks = data.ask || [], tot = (data.totalBidQty || 0) + (data.totalAskQty || 0) || 1;
      const spread = asks[0] && bids[0] ? (asks[0].price - bids[0].price).toFixed(2) : '--';
      setSpot(s => ({ ...s, bids: fmtS(data.totalBidQty || 0), asks: fmtS(data.totalAskQty || 0), bidPct: ((data.totalBidQty || 0) / tot) * 100, spread }));
      setLevels([...bids.slice(0, 5).map(b => ({ price: fmtP(b.price), size: fmtS(b.qty), side: 'bid', orders: b.orders })),
                 ...asks.slice(0, 5).map(a => ({ price: fmtP(a.price), size: fmtS(a.qty), side: 'ask', orders: a.orders }))]);
      dirty = true;
    } catch { /* depth non-critical */ }
  }

  async function loadData(sym, intervalStr) {
    setLoading(true);
    try {
      const res = await fetch(`/api/candles/${sym}?interval=${intervalStr}&days=5`, { headers: dashboardApiHeaders() });
      const data = await res.json();
      loadRealCandlesIntoSession(state, data.candles || [], sym);
    } catch { /* fallback */ }
    view.center = Math.max(20, state.bars.length - 25);
    fitViewPrices(view, state.bars, state.playhead);
    updateStats(); await fetchDepthData(sym);
    dirty = true; setLoading(false);
  }

  function updateStats() {
    const fv = getFormingValues(state);
    if (!fv.b) return;
    const firstOpen = state.bars[0]?.o || fv.cur, d = fv.cur - firstOpen, up = d >= 0;
    setSpot(s => ({ ...s, price: fmtP(fv.cur), delta: (up ? '+' : '') + ((d / firstOpen) * 100).toFixed(2) + '%', up }));
    setTape(state.events.slice(-12).reverse());
  }

  function scheduleNextMinuteFetch() {
    const now = new Date(), msUntilNext = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
    boundaryTimer = setTimeout(() => {
      if (isCandleBoundary(tf(), new Date())) loadData(symbol(), tf());
      scheduleNextMinuteFetch();
    }, msUntilNext + 2000);
  }

  createEffect(() => {
    localStorage.setItem('smc_symbol', symbol());
    localStorage.setItem('smc_interval', tf());
    localStorage.setItem('smc_palette', palette());
  });

  createEffect(() => {
    const key = symbol().toLowerCase(), ind = indices();
    if (ind && ind[key] && !playing()) {
      pushLiveTick(state, ind[key]); updateStats(); dirty = true;
    }
  });

  function animate(now) {
    const dt = Math.min(50, now - prevT); prevT = now;
    if (playing() && !halted()) {
      state.playhead += dt / (1600 / speed());
      if (state.playhead >= state.bars.length - 1) setPlaying(false);
      updateStats(); dirty = true;
    }
    fitViewPrices(view, state.bars, state.playhead);
    renderFrame(); animId = requestAnimationFrame(animate);
  }

  function renderFrame() {
    if (!sceneRef || !overRef) return;
    const sc = sceneRef.getContext('2d'), oc = overRef.getContext('2d'), bw = plot.w / view.visible;
    const cfg = SYMBOL_CONFIG[symbol()] || SYMBOL_CONFIG.NIFTY, aggData = getAggregatedBook(state, cfg.defaultBin, aggCache);
    if (dirty) {
      sc.setTransform(dpr, 0, 0, dpr, 0, 0); sc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
      drawGrid(sc, view, plot, state.bars, dpr, bw, 64);
      drawHeatmap(sc, view, plot, state, { heat: layers().heat, bin: cfg.defaultBin, gamma: 0.8 }, aggData, lut, bw);
      drawFvgAndRays(sc, view, plot, state, layers());
      if (layers().sr || layers().pos) drawKeyLevelsAndPositions(sc, view, plot, { levels: layers().sr ? buyingState() : null, positions: layers().pos ? chartPositions() : [] });
      drawCandlesAndVolume(sc, view, plot, state, { vol: layers().vol, candle: candleStyle() }, 0, state.bars.length - 1, bw);
      dirty = false;
    }
    oc.setTransform(dpr, 0, 0, dpr, 0, 0); oc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
    renderOverlay(oc, bw, aggData, cfg);
  }

  function renderOverlay(oc, bw, aggData, cfg) {
    const fv = getFormingValues(state);
    drawDepthProfile(oc, plot, view, state.liveDepth, aggData[Math.floor(state.playhead)] || new Map(), fv.cur, cfg.defaultBin, 90);
    const chips = [{ y0: getY(fv.cur, view, plot), h: 16, bg: fv.cur >= (fv.b?.o || 0) ? C.bid : C.ask, fg: '#04070F', txt: fmtP(fv.cur) }];
    const bs = layers().sr ? buyingState() : null;
    if (bs?.support) chips.push({ y0: getY(bs.support, view, plot), h: 15, bg: '#10B981', fg: '#04070F', txt: `S ${bs.support.toFixed(0)}` });
    if (bs?.resistance) chips.push({ y0: getY(bs.resistance, view, plot), h: 15, bg: '#FF4D6D', fg: '#04070F', txt: `R ${bs.resistance.toFixed(0)}` });
    if (layers().pos) {
      for (const p of chartPositions()) {
        const ent = Number(p.entry_price || p.buy_price);
        if (Number.isFinite(ent)) chips.push({ y0: getY(ent, view, plot), h: 15, bg: p.pnl >= 0 ? '#10B981' : '#FF4D6D', fg: '#FFF', txt: `POS ${ent.toFixed(1)}` });
      }
    }
    drawChips(oc, plot, 64, chips);
    if (hover && !drag) drawCrosshair(oc, hover, plot, view, 64, state.bars, bw);
  }

  onMount(() => {
    loadData(symbol(), tf()); resize(); window.addEventListener('resize', resize);
    animId = requestAnimationFrame(animate); pollTimer = setInterval(() => fetchDepthData(symbol()), 4000);
    scheduleNextMinuteFetch();
  });
  onCleanup(() => {
    window.removeEventListener('resize', resize);
    if (animId) cancelAnimationFrame(animId);
    if (pollTimer) clearInterval(pollTimer);
    if (boundaryTimer) clearTimeout(boundaryTimer);
  });
  const toggleL = (k) => { setLayers(l => ({ ...l, [k]: !l[k] })); dirty = true; };

  return (
    <div class="h-screen w-screen bg-[#04070F] text-[#E9EFFA] flex flex-col font-mono select-none overflow-hidden">
      <header class="h-14 border-b border-[#182742] bg-[#070D1A]/90 px-4 flex items-center justify-between z-20 backdrop-blur">
        <div class="flex items-center gap-3">
          <A href="/" class="text-xs text-[#8CA0BF] hover:text-[#3FC1FF] transition font-bold">← DASHBOARD</A>
          <div class="h-4 w-px bg-[#24375E]" />
          <span class="text-xs font-black text-white tracking-wider hidden sm:inline">SMC TERMINAL</span>
          <select value={symbol()} onChange={(e) => { setSymbol(e.target.value); loadData(e.target.value, tf()); }}
            class="bg-[#101C30] border border-[#24375E] rounded px-2.5 py-1 text-xs font-bold text-[#3FC1FF] cursor-pointer">
            <For each={SYMBOLS}>{(s) => <option value={s}>{s}</option>}</For>
          </select>
          <span class="text-[10px] px-2 py-0.5 rounded border border-[#8F7BFF]/40 text-[#8F7BFF]">{SYMBOL_CONFIG[symbol()]?.exch || 'INDEX'}</span>
          <div class="flex bg-[#070D1A] rounded p-0.5 border border-[#182742]">
            <For each={TIMEFRAMES}>
              {(t) => (
                <button onClick={() => { setTf(t.id); loadData(symbol(), t.id); }}
                  class={`px-2 py-0.5 rounded text-[10px] ${tf() === t.id ? 'bg-[#152441] text-[#3FC1FF] font-bold' : 'text-[#8CA0BF]'}`}>{t.lbl}</button>
              )}
            </For>
          </div>
          <Show when={chartPositions().length > 0}>
            <span class="text-[10px] font-bold px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">{chartPositions().length} POS OPEN</span>
          </Show>
        </div>
        <div class="flex items-center gap-3 text-xs">
          <Show when={loading()}><span class="text-[10px] text-[#3FC1FF] animate-pulse">SYNCING...</span></Show>
          <span class={spot().up ? 'text-[#19E3B1] font-bold text-sm' : 'text-[#FF4D6D] font-bold text-sm'}>{spot().price}</span>
          <span class={spot().up ? 'text-[#19E3B1] text-xs' : 'text-[#FF4D6D] text-xs'}>{spot().delta}</span>
          <button onClick={() => audio.setMuted(audio.isSoundOn())} class="px-2.5 py-1 rounded border border-[#24375E] bg-[#101C30] text-[10px]">{audio.isSoundOn() ? '🔊 SOUND' : '🔇 MUTED'}</button>
          <button onClick={() => { setHalted(!halted()); audio.kill(); }} class={`px-2.5 py-1 rounded border text-[10px] font-bold ${halted() ? 'border-[#19E3B1] text-[#19E3B1]' : 'border-[#FF3B5C] text-[#FF3B5C]'}`}>{halted() ? '⏻ RESUME' : '⏻ KILL SWITCH'}</button>
        </div>
      </header>

      <div class="flex-1 flex min-h-0 relative">
        <div ref={wrapRef} class="flex-1 relative overflow-hidden bg-gradient-to-b from-[#070D1A] to-[#04070F]"
          onPointerDown={(e) => { audio.init(); audio.resume(); drag = { x: e.offsetX, center: view.center }; }}
          onPointerMove={(e) => { if (drag) { view.center = drag.center - (e.offsetX - drag.x) / (plot.w / view.visible); dirty = true; } hover = { px: e.offsetX, py: e.offsetY }; }}
          onPointerUp={() => { drag = null; }}
          onWheel={(e) => { e.preventDefault(); view.visible = clamp(view.visible * (e.deltaY > 0 ? 1.08 : 0.92), 20, 300); dirty = true; }}>
          <canvas ref={sceneRef} class="absolute inset-0 pointer-events-none" />
          <canvas ref={overRef} class="absolute inset-0 cursor-crosshair" />

          {/* Options Buying HUD Overlay */}
          <Show when={layers().hud && buyingState()}>
            <div class="absolute top-3 left-3 z-10 p-3 rounded-xl bg-[#0B1424]/85 backdrop-blur-md border border-[#182742] shadow-2xl opacity-60 hover:opacity-100 transition-opacity pointer-events-auto">
              <div class="flex items-center gap-2 mb-2"><div class="w-2 h-2 rounded-full bg-[#3FC1FF] animate-pulse" /><span class="text-[9px] font-bold text-[#8CA0BF] uppercase tracking-widest">Options Buyer Core</span></div>
              <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-[11px] font-mono">
                <span class="text-[#8CA0BF]">Regime</span><span class={`font-bold text-right ${buyingState().regime?.includes('BULL') ? 'text-[#19E3B1]' : buyingState().regime?.includes('BEAR') ? 'text-[#FF4D6D]' : 'text-[#FFB224]'}`}>{buyingState().regime || 'UNKNOWN'}</span>
                <span class="text-[#8CA0BF]">Breakout</span><span class={`font-bold text-right ${buyingState().breakout_ready ? 'text-[#19E3B1]' : 'text-[#8CA0BF]'}`}>{buyingState().breakout_ready ? `[ARMED: ${buyingState().direction}]` : '[RANGING]'}</span>
                <span class="text-[#8CA0BF]">ATR Squeeze</span><span class={`font-bold text-right ${buyingState().compression_armed ? 'text-[#19E3B1]' : 'text-[#8CA0BF]'}`}>{buyingState().compression_armed ? 'YES' : 'NO'}</span>
                <span class="text-[#8CA0BF]">Daily ATR</span><span class="text-[#E9EFFA] text-right">{buyingState().daily_atr ? Number(buyingState().daily_atr).toFixed(2) : '--'}</span>
                <Show when={buyingState().support && buyingState().resistance}>
                  <span class="text-[#8CA0BF]">Key S/R</span><span class="text-[#E9EFFA] text-right font-bold"><span class="text-[#19E3B1]">S:{buyingState().support?.toFixed(0)}</span> / <span class="text-[#FF4D6D]">R:{buyingState().resistance?.toFixed(0)}</span></span>
                </Show>
                <Show when={buyingState().radar_strikes?.length > 0}>
                  <span class="text-[#8CA0BF]">Radar</span><span class="text-[#3FC1FF] text-right font-bold truncate max-w-[120px]">{buyingState().radar_strikes.map(s => typeof s === 'object' && s ? `${s.strike} ${s.type}` : s).join(', ')}</span>
                </Show>
              </div>
            </div>
          </Show>
        </div>

        <aside class="w-72 border-l border-[#182742] bg-[#0B1424] flex flex-col p-3 z-10 max-md:hidden">
          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-1">Live Order Book Imbalance</div>
          <div class="text-[9px] text-gray-500 mb-2">spread: {spot().spread} pts</div>
          <div class="h-2 rounded bg-[#070D1A] overflow-hidden flex mb-2">
            <div class="bg-[#19E3B1] transition-all" style={{ width: `${spot().bidPct}%` }} /><div class="bg-[#FF4D6D] transition-all" style={{ width: `${100 - spot().bidPct}%` }} />
          </div>
          <div class="flex justify-between text-[10px] mb-3"><span class="text-[#19E3B1]">Bids: {spot().bids}</span><span class="text-[#FF4D6D]">Asks: {spot().asks}</span></div>
          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-1">Resting Depth (DhanHQ)</div>
          <div class="h-28 overflow-y-auto space-y-1 mb-3">
            <For each={levels()}>{(lvl) => (
              <div class="flex justify-between items-center text-xs p-1 rounded bg-[#101C30]/50 border border-[#182742]">
                <span class={lvl.side === 'bid' ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{lvl.price}</span><span class="text-[#8CA0BF] text-[10px]">{lvl.size} ({lvl.orders}o)</span>
              </div>
            )}</For>
          </div>

          <Show when={chartPositions().length > 0}>
            <div class="text-[10px] tracking-widest text-emerald-400 uppercase mb-1">Open Positions ({chartPositions().length})</div>
            <div class="max-h-32 overflow-y-auto space-y-1 mb-3">
              <For each={chartPositions()}>{(p) => (
                <div class="p-1.5 rounded bg-[#101C30] border border-[#182742] flex flex-col gap-1 text-[10px]">
                  <div class="flex justify-between font-bold">
                    <span class="text-[#3FC1FF] truncate max-w-[130px]">{p.trading_symbol || p.symbol || p.index_key}</span>
                    <span class={Number(p.pnl || 0) >= 0 ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{Number(p.pnl || 0) >= 0 ? '+' : ''}{Number(p.pnl || 0).toFixed(2)}</span>
                  </div>
                  <div class="flex justify-between items-center text-[#8CA0BF]">
                    <span>Buy: {fmtP(p.entry_price || p.buy_price)}</span>
                    <button onClick={() => closeOpenPosition(p.id)} disabled={closingPositionId() === p.id}
                      class="px-1.5 py-0.5 rounded bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 font-bold border border-rose-500/30">
                      {closingPositionId() === p.id ? '...' : 'EXIT'}
                    </button>
                  </div>
                </div>
              )}</For>
            </div>
          </Show>

          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-1">Live Liquidity Tape</div>
          <div class="flex-1 min-h-[80px] overflow-y-auto space-y-1 border-t border-[#182742] pt-2">
            <For each={tape()}>{(ev) => (
              <div class="flex justify-between text-[10px] text-[#8CA0BF]"><span class={ev.side === 'bid' ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{ev.side.toUpperCase()} WALL @ {fmtP(ev.price)}</span><span>{fmtS(ev.size)}</span></div>
            )}</For>
          </div>
        </aside>
      </div>

      <footer class="h-16 border-t border-[#182742] bg-[#070D1A]/95 px-4 flex items-center justify-between text-xs z-20">
        <div class="flex items-center gap-3">
          <button onClick={() => { setPlaying(!playing()); audio.ui(); }} class="px-3 py-1.5 rounded bg-[#8F7BFF]/20 border border-[#8F7BFF]/50 text-[#8F7BFF] font-bold">
            {playing() ? '❚❚ PAUSE' : '▶ PLAY'}
          </button>
          <select value={speed()} onChange={(e) => setSpeed(Number(e.target.value))} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[11px]">
            <option value="0.5">0.5×</option><option value="1">1.0×</option><option value="2">2.0×</option><option value="4">4.0×</option>
          </select>
          <input type="range" min="1" max={Math.max(10, state.bars.length - 1)} value={Math.floor(state.playhead)}
            onInput={(e) => { state.playhead = Number(e.target.value); updateStats(); dirty = true; }} class="w-28 accent-[#3FC1FF]" />
        </div>
        <div class="flex items-center gap-1.5 overflow-x-auto">
          <For each={LAYER_KEYS}>{(k) => (
            <button onClick={() => toggleL(k)} class={`px-2 py-1 rounded border text-[10px] ${layers()[k] ? 'border-[#3FC1FF] text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF]'}`}>{k.toUpperCase()}</button>
          )}</For>
          <button onClick={() => { setCandleStyle(s => s === 'hollow' ? 'solid' : 'hollow'); dirty = true; }} class="px-2 py-1 rounded border border-[#24375E] text-[#8CA0BF] text-[10px]">
            {candleStyle().toUpperCase()}
          </button>
          <select value={palette()} onChange={(e) => { setPalette(e.target.value); lut = buildLUT(e.target.value); dirty = true; }} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[10px]">
            <option value="ion">Ion Heat</option><option value="classic">Classic</option><option value="ultra">Ultraviolet</option>
          </select>
        </div>
      </footer>
    </div>
  );
}

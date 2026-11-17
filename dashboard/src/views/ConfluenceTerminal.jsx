import { createSignal, createEffect, onMount, onCleanup, For, Show } from 'solid-js';
import { A } from '@solidjs/router';
import { dashboardApiHeaders } from '../lib/dashboardApi';
import { useDashboard } from '../stores/useDashboard';
import {
  SEEDS, SYMBOL_CONFIG, clamp, createSessionState, ensureBars,
  restoreEngineTo, getAggregatedBook, getFormingValues,
  loadRealCandlesIntoSession, pushLiveTick
} from '../lib/confluence/engine';
import { createAudioEngine } from '../lib/confluence/audio';
import {
  C, PALETTES, fmtP, fmtS, fmtT, buildLUT, getY,
  drawGrid, drawHeatmap, drawFvgAndRays, drawCandlesAndVolume,
  drawChips, drawDepthProfile, drawCrosshair, fitViewPrices
} from '../lib/confluence/renderer';

const SYMBOLS = ['NIFTY', 'BANKNIFTY', 'SENSEX', 'SIM_SOL'];
const TIMEFRAMES = [{ id: '1', lbl: '1m' }, { id: '5', lbl: '5m' }, { id: '15', lbl: '15m' }, { id: '60', lbl: '1h' }];

export default function ConfluenceTerminal() {
  let wrapRef, sceneRef, overRef;
  const audio = createAudioEngine();
  const { indices } = useDashboard();
  const [symbol, setSymbol] = createSignal('NIFTY');
  const [tf, setTf] = createSignal('5');
  const [playing, setPlaying] = createSignal(false);
  const [halted, setHalted] = createSignal(false);
  const [speed, setSpeed] = createSignal(1);
  const [palette, setPalette] = createSignal('ion');
  const [layers, setLayers] = createSignal({ heat: true, fvg: true, vol: true });
  const [spot, setSpot] = createSignal({ price: '--', delta: '0.00%', up: true, bids: '0', asks: '0', bidPct: 50 });
  const [levels, setLevels] = createSignal([]);
  const [tape, setTape] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

  let state = createSessionState(SEEDS[0], 5, 'NIFTY');
  let aggCache = { bin: 10, len: 0, data: [], symbol: 'NIFTY' };
  let lut = buildLUT('ion');
  let view = { center: 50, visible: 70, minP: 24000, maxP: 26000 };
  let plot = { x: 8, y: 8, w: 800, h: 500, r: 808, b: 508 };
  let dirty = true, dpr = Math.min(2, window.devicePixelRatio || 1), hover = null, drag = null, animId = null, prevT = performance.now();

  function resize() {
    if (!wrapRef || !sceneRef || !overRef) return;
    const r = wrapRef.getBoundingClientRect();
    const w = Math.max(80, r.width), h = Math.max(80, r.height);
    for (const cv of [sceneRef, overRef]) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    const axisW = w < 560 ? 56 : 72;
    plot = { x: 8, y: 8, w: w - axisW - 12, h: h - 40, r: w - axisW - 4, b: h - 32 };
    dirty = true;
  }

  async function loadData(sym, intervalStr) {
    setLoading(true);
    const cfg = SYMBOL_CONFIG[sym] || SYMBOL_CONFIG.NIFTY;
    if (sym === 'SIM_SOL') {
      state = createSessionState(SEEDS[0], parseInt(intervalStr, 10), 'SIM_SOL');
      ensureBars(state, 180);
      restoreEngineTo(state, 160);
    } else {
      try {
        const res = await fetch(`/api/candles/${sym}?interval=${intervalStr}&days=2`, { headers: dashboardApiHeaders() });
        const data = await res.json();
        loadRealCandlesIntoSession(state, data.candles || [], sym);
      } catch {
        ensureBars(state, 120);
      }
    }
    view.center = Math.max(20, state.bars.length - 25);
    fitViewPrices(view, state.bars, state.playhead);
    updateStats();
    dirty = true;
    setLoading(false);
  }

  function updateStats() {
    const fv = getFormingValues(state);
    if (!fv.b) return;
    const firstOpen = state.bars[0]?.o || fv.cur;
    const d = fv.cur - firstOpen;
    const up = d >= 0;
    let bt = 0, at = 0;
    for (const [idx, s] of state.book) {
      const p = idx * state.baseBin;
      if (Math.abs(p - fv.cur) <= state.baseBin * 20) { if (p < fv.cur) bt += s; else at += s; }
    }
    const tot = bt + at || 1;
    setSpot({ price: fmtP(fv.cur), delta: (up ? '+' : '') + ((d / firstOpen) * 100).toFixed(2) + '%',
      up, bids: fmtS(bt), asks: fmtS(at), bidPct: (bt / tot) * 100 });
    const f = Math.floor(state.playhead);
    setLevels((state.bigsSnap[f] || []).slice(0, 15).map(b => ({ price: fmtP(b.idx * state.baseBin), size: fmtS(b.size), side: b.side })));
    setTape(state.events.filter(e => e.bar <= f).slice(-12).reverse());
  }

  createEffect(() => {
    const key = symbol().toLowerCase();
    const ind = indices();
    if (ind && ind[key] && !playing()) {
      pushLiveTick(state, ind[key]);
      updateStats();
      dirty = true;
    }
  });

  function animate(now) {
    const dt = Math.min(50, now - prevT);
    prevT = now;
    if (playing() && !halted()) {
      const prevFloor = Math.floor(state.playhead);
      state.playhead += dt / (1600 / speed());
      if (state.playhead >= state.bars.length - 1) setPlaying(false);
      const f = Math.floor(state.playhead);
      if (f !== prevFloor) {
        restoreEngineTo(state, f);
        updateStats();
        dirty = true;
      }
    }
    fitViewPrices(view, state.bars, state.playhead);
    renderFrame(now);
    animId = requestAnimationFrame(animate);
  }

  function renderFrame(now) {
    if (!sceneRef || !overRef) return;
    const sc = sceneRef.getContext('2d'), oc = overRef.getContext('2d');
    const bw = plot.w / view.visible, cfg = SYMBOL_CONFIG[symbol()] || SYMBOL_CONFIG.NIFTY;
    const aggData = getAggregatedBook(state, cfg.defaultBin, aggCache);
    if (dirty) {
      sc.setTransform(dpr, 0, 0, dpr, 0, 0);
      sc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
      drawGrid(sc, view, plot, state.bars, dpr, bw, 64);
      drawHeatmap(sc, view, plot, state, { heat: layers().heat, bin: cfg.defaultBin, gamma: 0.8 }, aggData, lut, bw);
      drawFvgAndRays(sc, view, plot, state, layers(), Math.floor(state.playhead), bw);
      drawCandlesAndVolume(sc, view, plot, state, { vol: layers().vol, candle: 'hollow' }, 0, state.bars.length - 1, bw);
      dirty = false;
    }
    oc.setTransform(dpr, 0, 0, dpr, 0, 0);
    oc.clearRect(0, 0, wrapRef.clientWidth, wrapRef.clientHeight);
    renderOverlay(oc, bw, aggData, cfg);
  }

  function renderOverlay(oc, bw, aggData, cfg) {
    const fv = getFormingValues(state);
    const m = aggData[Math.floor(state.playhead)] || new Map();
    drawDepthProfile(oc, plot, view, m, fv.cur, cfg.defaultBin, 90);
    const chips = [{ y0: getY(fv.cur, view, plot), h: 16, bg: fv.cur >= fv.b?.o ? C.bid : C.ask, fg: '#04070F', txt: fmtP(fv.cur) }];
    drawChips(oc, plot, 64, chips);
    if (hover && !drag) drawCrosshair(oc, hover, plot, view, 64, state.bars, bw);
  }

  onMount(() => {
    loadData(symbol(), tf());
    resize();
    window.addEventListener('resize', resize);
    animId = requestAnimationFrame(animate);
  });

  onCleanup(() => {
    window.removeEventListener('resize', resize);
    if (animId) cancelAnimationFrame(animId);
  });

  const toggleL = (k) => setLayers(l => ({ ...l, [k]: !l[k] }));

  return (
    <div class="h-screen w-screen bg-[#04070F] text-[#E9EFFA] flex flex-col font-mono select-none overflow-hidden">
      <header class="h-14 border-b border-[#182742] bg-[#070D1A]/90 px-4 flex items-center justify-between z-20 backdrop-blur">
        <div class="flex items-center gap-3">
          <A href="/charts" class="text-xs text-[#8CA0BF] hover:text-[#3FC1FF] transition">← CHARTS</A>
          <div class="h-4 w-px bg-[#24375E]" />
          <select value={symbol()} onChange={(e) => { setSymbol(e.target.value); loadData(e.target.value, tf()); }}
            class="bg-[#101C30] border border-[#24375E] rounded px-2.5 py-1 text-xs font-bold text-[#3FC1FF] cursor-pointer">
            <For each={SYMBOLS}>{(s) => <option value={s}>{s}</option>}</For>
          </select>
          <span class="text-[10px] px-2 py-0.5 rounded border border-[#8F7BFF]/40 text-[#8F7BFF]">
            {SYMBOL_CONFIG[symbol()]?.exch || 'INDEX'}
          </span>
          <div class="flex bg-[#070D1A] rounded p-0.5 border border-[#182742]">
            <For each={TIMEFRAMES}>
              {(t) => (
                <button onClick={() => { setTf(t.id); loadData(symbol(), t.id); }}
                  class={`px-2 py-0.5 rounded text-[10px] ${tf() === t.id ? 'bg-[#152441] text-[#3FC1FF] font-bold' : 'text-[#8CA0BF]'}`}>
                  {t.lbl}
                </button>
              )}
            </For>
          </div>
        </div>

        <div class="flex items-center gap-3 text-xs">
          <Show when={loading()}><span class="text-[10px] text-[#3FC1FF] animate-pulse">SYNCING...</span></Show>
          <span class={spot().up ? 'text-[#19E3B1] font-bold text-sm' : 'text-[#FF4D6D] font-bold text-sm'}>{spot().price}</span>
          <span class={spot().up ? 'text-[#19E3B1] text-xs' : 'text-[#FF4D6D] text-xs'}>{spot().delta}</span>
          <button onClick={() => audio.setMuted(audio.isSoundOn())} class="px-2.5 py-1 rounded border border-[#24375E] bg-[#101C30] text-[10px]">
            {audio.isSoundOn() ? '🔊 SOUND' : '🔇 MUTED'}
          </button>
          <button onClick={() => { setHalted(!halted()); audio.kill(); }} class={`px-2.5 py-1 rounded border text-[10px] font-bold ${halted() ? 'border-[#19E3B1] text-[#19E3B1]' : 'border-[#FF3B5C] text-[#FF3B5C]'}`}>
            {halted() ? '⏻ RESUME' : '⏻ KILL SWITCH'}
          </button>
        </div>
      </header>

      <div class="flex-1 flex min-h-0 relative">
        <div ref={wrapRef} class="flex-1 relative overflow-hidden bg-gradient-to-b from-[#070D1A] to-[#04070F]"
          onPointerDown={(e) => { audio.init(); audio.resume(); drag = { x: e.offsetX, center: view.center }; }}
          onPointerMove={(e) => {
            if (drag) { view.center = drag.center - (e.offsetX - drag.x) / (plot.w / view.visible); dirty = true; }
            hover = { px: e.offsetX, py: e.offsetY };
          }}
          onPointerUp={() => { drag = null; }}
          onWheel={(e) => {
            e.preventDefault();
            view.visible = clamp(view.visible * (e.deltaY > 0 ? 1.08 : 0.92), 20, 300);
            dirty = true;
          }}
        >
          <canvas ref={sceneRef} class="absolute inset-0 pointer-events-none" />
          <canvas ref={overRef} class="absolute inset-0 cursor-crosshair" />
        </div>

        <aside class="w-72 border-l border-[#182742] bg-[#0B1424] flex flex-col p-3 z-10 max-md:hidden">
          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-2">Order Book Imbalance</div>
          <div class="h-2 rounded bg-[#070D1A] overflow-hidden flex mb-2">
            <div class="bg-[#19E3B1] transition-all" style={{ width: `${spot().bidPct}%` }} />
            <div class="bg-[#FF4D6D] transition-all" style={{ width: `${100 - spot().bidPct}%` }} />
          </div>
          <div class="flex justify-between text-[10px] mb-4">
            <span class="text-[#19E3B1]">Bids: {spot().bids}</span>
            <span class="text-[#FF4D6D]">Asks: {spot().asks}</span>
          </div>

          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-1">Resting Levels</div>
          <div class="flex-1 overflow-y-auto space-y-1 mb-3">
            <For each={levels()}>
              {(lvl) => (
                <div class="flex justify-between items-center text-xs p-1.5 rounded bg-[#101C30]/50 border border-[#182742]">
                  <span class={lvl.side === 'bid' ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{lvl.price}</span>
                  <span class="text-[#8CA0BF] text-[10px]">{lvl.size}</span>
                </div>
              )}
            </For>
          </div>

          <div class="text-[10px] tracking-widest text-[#8CA0BF] uppercase mb-1">Liquidity Tape</div>
          <div class="h-36 overflow-y-auto space-y-1 border-t border-[#182742] pt-2">
            <For each={tape()}>
              {(ev) => (
                <div class="flex justify-between text-[10px] text-[#8CA0BF]">
                  <span class={ev.type === 'held' ? 'text-[#9BE84C]' : ev.type === 'pull' ? 'text-[#FFB224]' : 'text-[#8F7BFF]'}>
                    {ev.type.toUpperCase()} @ {fmtP(ev.price)}
                  </span>
                  <span>{fmtS(ev.size)}</span>
                </div>
              )}
            </For>
          </div>
        </aside>
      </div>

      <footer class="h-16 border-t border-[#182742] bg-[#070D1A]/95 px-4 flex items-center justify-between text-xs z-20">
        <div class="flex items-center gap-3">
          <button onClick={() => { setPlaying(!playing()); audio.ui(); }} class="px-3 py-1.5 rounded bg-[#8F7BFF]/20 border border-[#8F7BFF]/50 text-[#8F7BFF] font-bold">
            {playing() ? '❚❚ PAUSE' : '▶ PLAY'}
          </button>
          <select value={speed()} onChange={(e) => setSpeed(Number(e.target.value))} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[11px]">
            <option value="0.5">0.5×</option>
            <option value="1">1.0×</option>
            <option value="2">2.0×</option>
            <option value="4">4.0×</option>
          </select>
          <input type="range" min="1" max={Math.max(10, state.bars.length - 1)} value={Math.floor(state.playhead)}
            onInput={(e) => {
              const val = Number(e.target.value);
              state.playhead = val;
              restoreEngineTo(state, val);
              updateStats();
              dirty = true;
            }}
            class="w-32 accent-[#3FC1FF]"
          />
        </div>

        <div class="flex items-center gap-2">
          <button onClick={() => toggleL('heat')} class={`px-2 py-1 rounded border text-[10px] ${layers().heat ? 'border-[#3FC1FF] text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF]'}`}>HEATMAP</button>
          <button onClick={() => toggleL('fvg')} class={`px-2 py-1 rounded border text-[10px] ${layers().fvg ? 'border-[#3FC1FF] text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF]'}`}>FVG</button>
          <button onClick={() => toggleL('vol')} class={`px-2 py-1 rounded border text-[10px] ${layers().vol ? 'border-[#3FC1FF] text-[#3FC1FF] bg-[#3FC1FF]/10' : 'border-[#24375E] text-[#8CA0BF]'}`}>VOLUME</button>
          <select value={palette()} onChange={(e) => { setPalette(e.target.value); lut = buildLUT(e.target.value); dirty = true; }} class="bg-[#101C30] border border-[#24375E] rounded px-2 py-1 text-[10px]">
            <option value="ion">Ion Heat</option>
            <option value="classic">Classic</option>
            <option value="ultra">Ultraviolet</option>
          </select>
        </div>
      </footer>
    </div>
  );
}

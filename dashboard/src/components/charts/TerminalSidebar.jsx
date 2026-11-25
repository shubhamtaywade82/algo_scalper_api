import { For, Show } from 'solid-js';
import { fmtP, fmtS, fmtT, fmtD } from '../../lib/confluence/renderer';
import { StraddleCard, GreeksCard, LadderCard } from './OptionsPanel';

const signed = (n, digits = 2) => `${n >= 0 ? '+' : ''}${Number(n).toFixed(digits)}`;
const tone = (up) => (up ? 'text-[#19E3B1]' : 'text-[#FF4D6D]');

function Section(props) {
  return (
    <section class="px-4 py-3 border-b border-[#182742]">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-[10px] tracking-[0.18em] uppercase text-[#8CA0BF] font-bold">{props.title}</h3>
        {props.badge}
      </div>
      {props.children}
    </section>
  );
}

function Row(props) {
  return (
    <div class="flex justify-between items-baseline text-[11px] leading-5">
      <span class="text-[#8CA0BF]">{props.label}</span>
      <span class={`font-bold tabular-nums ${props.class || 'text-[#E9EFFA]'}`}>{props.children}</span>
    </div>
  );
}

function RangeBar(props) {
  const pct = () => {
    const span = props.high - props.low;
    return span > 0 ? Math.min(100, Math.max(0, ((props.price - props.low) / span) * 100)) : 50;
  };
  return (
    <div class="mt-2">
      <div class="relative h-1.5 rounded bg-[#101C30]">
        <div class="absolute inset-y-0 left-0 rounded bg-gradient-to-r from-[#FF4D6D]/60 to-[#19E3B1]/60" style={{ width: `${pct()}%` }} />
        <div class="absolute -top-0.5 w-1 h-2.5 rounded bg-white" style={{ left: `calc(${pct()}% - 2px)` }} />
      </div>
      <div class="flex justify-between text-[10px] text-[#8CA0BF] mt-1 tabular-nums"><span>L {fmtP(props.low)}</span><span>H {fmtP(props.high)}</span></div>
    </div>
  );
}

function InstrumentCard(props) {
  const s = () => props.spot;
  return (
    <Section title={props.symbol} badge={<span class="text-[9px] text-[#5A6C8C]">PREV {fmtP(s().base)}</span>}>
      <div class="flex items-baseline gap-2">
        <span class={`text-2xl font-black tabular-nums ${tone(s().up)}`}>{fmtP(s().price)}</span>
        <span class={`text-xs font-bold tabular-nums ${tone(s().up)}`}>{signed(s().change)} ({signed(s().pct)}%)</span>
      </div>
      <Show when={s().dayHigh > 0}><RangeBar low={s().dayLow} high={s().dayHigh} price={s().price} /></Show>
    </Section>
  );
}

function BarCard(props) {
  const b = () => props.bar;
  return (
    <Section title={props.hovering ? 'Bar (hover)' : 'Forming bar'} badge={<Show when={b()}><span class="text-[9px] text-[#5A6C8C]">{fmtD(b().t)} {fmtT(b().t)} IST</span></Show>}>
      <Show when={b()} fallback={<span class="text-[11px] text-[#5A6C8C]">no data</span>}>
        <div class="grid grid-cols-2 gap-x-4">
          <Row label="Open">{fmtP(b().o)}</Row><Row label="High" class="text-[#19E3B1]">{fmtP(b().h)}</Row>
          <Row label="Low" class="text-[#FF4D6D]">{fmtP(b().l)}</Row><Row label="Close" class={tone(b().c >= b().o)}>{fmtP(b().c)}</Row>
        </div>
        <Row label="Range">{(b().h - b().l).toFixed(2)} pts</Row>
        <Row label="Volume">{fmtS(b().v)}</Row>
      </Show>
    </Section>
  );
}

function RegimeCard(props) {
  const bs = () => props.state;
  const regimeTone = () => (bs().regime?.includes('BULL') ? 'text-[#19E3B1]' : bs().regime?.includes('BEAR') ? 'text-[#FF4D6D]' : 'text-[#FFB224]');
  return (
    <Section title="Options Buyer Core">
      <Show when={bs()} fallback={<span class="text-[11px] text-[#5A6C8C]">awaiting analysis</span>}>
        <Row label="Regime" class={regimeTone()}>{bs().regime || 'UNKNOWN'}</Row>
        <Row label="Breakout" class={bs().breakout_ready ? 'text-[#19E3B1]' : 'text-[#8CA0BF]'}>{bs().breakout_ready ? `ARMED ${bs().direction || ''}` : 'RANGING'}</Row>
        <Row label="ATR squeeze" class={bs().compression_armed ? 'text-[#19E3B1]' : 'text-[#8CA0BF]'}>{bs().compression_armed ? 'YES' : 'NO'}</Row>
        <Row label="Daily ATR">{bs().daily_atr ? Number(bs().daily_atr).toFixed(2) : '--'}</Row>
        <Show when={bs().support && bs().resistance}>
          <Row label="Support / Resistance"><span class="text-[#19E3B1]">{Number(bs().support).toFixed(0)}</span> / <span class="text-[#FF4D6D]">{Number(bs().resistance).toFixed(0)}</span></Row>
        </Show>
      </Show>
    </Section>
  );
}

function PositionsCard(props) {
  return (
    <Show when={props.positions.length > 0}>
      <Section title={`Open positions (${props.positions.length})`}>
        <div class="space-y-1.5">
          <For each={props.positions}>{(p) => (
            <div class="p-2 rounded bg-[#101C30] border border-[#182742] text-[10px]">
              <div class="flex justify-between font-bold">
                <span class="text-[#3FC1FF] truncate max-w-[150px]">{p.trading_symbol || p.symbol || p.index_key}</span>
                <span class={`tabular-nums ${tone(Number(p.pnl || 0) >= 0)}`}>{signed(p.pnl || 0)} ({signed(p.pnl_pct || 0, 1)}%)</span>
              </div>
              <div class="flex justify-between text-[#8CA0BF] mt-1 tabular-nums">
                <span>{fmtP(p.entry_price)} → <b class="text-[#E9EFFA]">{fmtP(p.ltp)}</b></span>
                <span><span class="text-[#FF4D6D]">SL {p.sl_price ? fmtP(p.sl_price) : '--'}</span> · <span class="text-[#19E3B1]">TP {p.tp_price ? fmtP(p.tp_price) : '--'}</span></span>
              </div>
              <div class="flex justify-end mt-1">
                <button onClick={() => props.onExit(p.id)} disabled={props.closingId === p.id}
                  class="px-2 py-0.5 rounded bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 font-bold border border-rose-500/30 disabled:opacity-50">
                  {props.closingId === p.id ? '...' : 'EXIT'}
                </button>
              </div>
            </div>
          )}</For>
        </div>
      </Section>
    </Show>
  );
}

function DepthRow(props) {
  const widthPct = () => `${Math.min(100, (props.level.qty / props.max) * 100)}%`;
  const bar = () => (props.side === 'bid' ? 'bg-[#19E3B1]/20' : 'bg-[#FF4D6D]/20');
  return (
    <div class="relative flex justify-between text-[10px] px-1.5 py-0.5 rounded overflow-hidden tabular-nums">
      <div class={`absolute inset-y-0 right-0 ${bar()}`} style={{ width: widthPct() }} />
      <span class={`relative ${props.side === 'bid' ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}`}>{fmtP(props.level.price)}</span>
      <span class="relative text-[#8CA0BF]">{fmtS(props.level.qty)} <span class="text-[#5A6C8C]">({props.level.orders})</span></span>
    </div>
  );
}

function DepthCard(props) {
  const d = () => props.depth;
  const max = () => Math.max(1, ...d().bid.map((l) => l.qty), ...d().ask.map((l) => l.qty));
  const state = () => (d().error ? 'UNAVAILABLE' : d().at ? 'LIVE' : 'LOADING');
  return (
    <Section title="ATM CE depth" badge={<span class={`text-[9px] font-bold ${d().error ? 'text-[#FFB224]' : 'text-[#8CA0BF]'}`}>{state()}</span>}>
      <div class="h-1.5 rounded bg-[#101C30] overflow-hidden flex mb-1.5">
        <div class="bg-[#19E3B1] transition-all" style={{ width: `${d().bidPct}%` }} />
        <div class="bg-[#FF4D6D] transition-all" style={{ width: `${100 - d().bidPct}%` }} />
      </div>
      <div class="flex justify-between text-[10px] mb-2 tabular-nums">
        <span class="text-[#19E3B1]">Bids {fmtS(d().totalBid)}</span><span class="text-[#8CA0BF]">spread {d().spread}</span><span class="text-[#FF4D6D]">Asks {fmtS(d().totalAsk)}</span>
      </div>
      <Show when={d().ask.length || d().bid.length} fallback={<span class="text-[11px] text-[#5A6C8C]">{d().error ? 'Dhan quote budget busy — retrying' : 'waiting for depth'}</span>}>
        <div class="space-y-px">
          <For each={[...d().ask].slice(0, 5).reverse()}>{(l) => <DepthRow level={l} side="ask" max={max()} />}</For>
          <div class="border-t border-dashed border-[#24375E] my-1" />
          <For each={d().bid.slice(0, 5)}>{(l) => <DepthRow level={l} side="bid" max={max()} />}</For>
        </div>
      </Show>
    </Section>
  );
}

export default function TerminalSidebar(props) {
  return (
    <aside class="w-80 shrink-0 border-l border-[#182742] bg-[#0B1424] overflow-y-auto z-10 max-md:hidden">
      <InstrumentCard symbol={props.symbol} spot={props.spot} />
      <PositionsCard positions={props.positions} onExit={props.onExit} closingId={props.closingId} />
      <Show when={props.options} fallback={<Section title="Option chain"><span class="text-[11px] text-[#5A6C8C]">waiting for option chain…</span></Section>}>
        <StraddleCard view={props.options} />
        <LadderCard view={props.options} />
        <GreeksCard view={props.options} />
      </Show>
      <DepthCard depth={props.depth} />
      <BarCard bar={props.bar} hovering={props.hovering} />
      <RegimeCard state={props.buyingState} />
    </aside>
  );
}

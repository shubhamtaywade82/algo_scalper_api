import { For, Show } from 'solid-js';
import { fmtP, fmtS } from '../../lib/confluence/renderer';

const num = (n, digits = 2) => (Number.isFinite(n) ? Number(n).toFixed(digits) : '--');
const rupees = (n) => (Number.isFinite(n) ? `₹${Math.round(n).toLocaleString('en-IN')}` : '--');

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

function Stat(props) {
  return (
    <div class="rounded bg-[#101C30] border border-[#182742] px-2 py-1.5">
      <div class="text-[9px] uppercase tracking-wider text-[#5A6C8C]">{props.label}</div>
      <div class={`text-sm font-black tabular-nums ${props.class || 'text-[#E9EFFA]'}`}>{props.children}</div>
    </div>
  );
}

export function StraddleCard(props) {
  const v = () => props.view;
  const dteTone = () => (v().dte <= 1 ? 'text-[#FFB224]' : 'text-[#8CA0BF]');
  return (
    <Section title={`ATM ${v().atm}`} badge={
      <span class={`text-[9px] font-bold ${v().stale ? 'text-[#FFB224]' : dteTone()}`}>{v().stale ? 'STALE · ' : ''}{v().expiry} · {v().dte}D</span>}>
      <div class="grid grid-cols-3 gap-1.5">
        <Stat label="CE" class="text-[#19E3B1]">{num(v().ce?.ltp)}</Stat>
        <Stat label="PE" class="text-[#FF4D6D]">{num(v().pe?.ltp)}</Stat>
        <Stat label="Straddle">{num(v().straddle)}</Stat>
      </div>
      <Show when={v().impliedMove}>
        <div class="mt-2 text-[10px] text-[#8CA0BF] tabular-nums flex justify-between">
          <span>Implied move ±{num(v().straddle, 0)} pts</span><span>{fmtP(v().impliedMove.down)} – {fmtP(v().impliedMove.up)}</span>
        </div>
      </Show>
      <div class="mt-1 text-[10px] text-[#8CA0BF] tabular-nums flex justify-between">
        <span>Breakeven <span class="text-[#19E3B1]">CE {num(v().breakeven.ce, 0)}</span> · <span class="text-[#FF4D6D]">PE {num(v().breakeven.pe, 0)}</span></span>
        <span>PCR <b class={v().pcr >= 1 ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{num(v().pcr)}</b></span>
      </div>
    </Section>
  );
}

const GREEK_ROWS = [
  ['Delta', (l) => num(l?.delta, 3)],
  ['Gamma', (l) => num(l?.gamma, 4)],
  ['Theta', (l) => num(l?.theta, 1)],
  ['Vega', (l) => num(l?.vega, 1)],
  ['IV %', (l) => num(l?.iv, 1)],
  ['Bid-ask %', (l) => (l?.ltp > 0 && l.ask > 0 && l.bid > 0 ? num(((l.ask - l.bid) / l.ltp) * 100, 2) : '--')],
  ['OI', (l) => (l ? fmtS(l.oi) : '--')],
  ['OI change', (l) => (l ? `${l.oi_change >= 0 ? '+' : ''}${fmtS(l.oi_change)}` : '--')],
  ['Volume', (l) => (l ? fmtS(l.volume) : '--')],
  ['Lot cost', (l) => rupees(l?.ltp * l?.lot_size)],
  ['Θ ₹/lot', (l) => rupees(l?.theta * l?.lot_size)]
];

export function GreeksCard(props) {
  return (
    <Section title="ATM greeks" badge={<span class="text-[9px] text-[#5A6C8C]">lot {props.view.ce?.lot_size ?? '--'}</span>}>
      <div class="grid grid-cols-[1fr_auto_auto] gap-x-3 text-[11px] leading-5 tabular-nums">
        <span /><span class="text-right text-[#19E3B1] font-bold">CE</span><span class="text-right text-[#FF4D6D] font-bold">PE</span>
        <For each={GREEK_ROWS}>{([label, read]) => (
          <>
            <span class="text-[#8CA0BF]">{label}</span>
            <span class="text-right text-[#E9EFFA] font-bold">{read(props.view.ce)}</span>
            <span class="text-right text-[#E9EFFA] font-bold">{read(props.view.pe)}</span>
          </>
        )}</For>
      </div>
    </Section>
  );
}

function OiBar(props) {
  const width = () => `${Math.min(100, ((props.leg?.oi || 0) / props.max) * 100)}%`;
  return (
    <div class="relative h-4 flex items-center px-1 overflow-hidden rounded-sm">
      <div class={`absolute inset-y-0 ${props.side === 'ce' ? 'right-0 bg-[#19E3B1]/15' : 'left-0 bg-[#FF4D6D]/15'}`} style={{ width: width() }} />
      <span class={`relative w-full tabular-nums ${props.side === 'ce' ? 'text-right text-[#19E3B1]' : 'text-left text-[#FF4D6D]'}`}>{num(props.leg?.ltp)}</span>
    </div>
  );
}

export function LadderCard(props) {
  const maxOi = () => Math.max(1, ...props.view.ladder.flatMap((r) => [r.ce?.oi || 0, r.pe?.oi || 0]));
  return (
    <Section title="Strike ladder" badge={<span class="text-[9px] text-[#5A6C8C]">bar = OI</span>}>
      <div class="grid grid-cols-[1fr_auto_1fr] gap-x-1.5 gap-y-px text-[10px]">
        <For each={props.view.ladder}>{(row) => (
          <>
            <OiBar leg={row.ce} side="ce" max={maxOi()} />
            <span class={`px-1.5 text-center tabular-nums leading-4 ${row.isAtm ? 'bg-[#152441] text-white font-black rounded' : 'text-[#8CA0BF]'}`}>{row.strike}</span>
            <OiBar leg={row.pe} side="pe" max={maxOi()} />
          </>
        )}</For>
      </div>
    </Section>
  );
}

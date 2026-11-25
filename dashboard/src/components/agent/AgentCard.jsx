import { For, Show } from 'solid-js'

const STATE_TONE = {
  IDLE: 'text-[#8CA0BF]', HALTED: 'text-[#FF4D6D]', POSITION_OPEN: 'text-[#19E3B1]', RISK_MANAGEMENT_ACTIVE: 'text-[#19E3B1]'
}
const OUTCOME_TONE = { accepted: 'text-[#19E3B1]', dropped: 'text-[#FFB224]', expired: 'text-[#8CA0BF]', unanswered: 'text-[#FF4D6D]' }

const inr = (n) => (Number.isFinite(n) ? `${n >= 0 ? '+' : '-'}₹${Math.abs(Math.round(n)).toLocaleString('en-IN')}` : '--')
const pnlTone = (n) => (n >= 0 ? 'text-[#19E3B1]' : 'text-[#FF4D6D]')
const hhmm = (minute) => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`
const time = (iso) => new Date(iso).toLocaleTimeString('en-GB', { timeZone: 'Asia/Kolkata', hour12: false })

function Header(props) {
  const s = () => props.status
  const label = () => (s().online ? 'ONLINE' : 'OFFLINE')
  return (
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-[10px] tracking-[0.18em] uppercase text-[#8CA0BF] font-bold">Execution agent</h3>
      <span class={`flex items-center gap-1.5 text-[9px] font-bold ${s().online ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}`}>
        <span class={`w-1.5 h-1.5 rounded-full ${s().online ? 'bg-[#19E3B1] animate-pulse' : 'bg-[#FF4D6D]'}`} />
        {label()} · {s().snapshot?.mode?.toUpperCase() || '--'} · engine {s().engine}
      </span>
    </div>
  )
}

function Summary(props) {
  const snap = () => props.snapshot
  return (
    <div class="grid grid-cols-3 gap-1.5 text-[10px] mb-2 tabular-nums">
      <div class="rounded bg-[#101C30] border border-[#182742] px-2 py-1">
        <div class="text-[#5A6C8C] uppercase">Realized</div>
        <div class={`font-black text-xs ${pnlTone(snap().day_pnl.realized_inr)}`}>{inr(snap().day_pnl.realized_inr)}</div>
      </div>
      <div class="rounded bg-[#101C30] border border-[#182742] px-2 py-1">
        <div class="text-[#5A6C8C] uppercase">Open</div>
        <div class={`font-black text-xs ${pnlTone(snap().day_pnl.unrealized_inr)}`}>{inr(snap().day_pnl.unrealized_inr)}</div>
      </div>
      <div class="rounded bg-[#101C30] border border-[#182742] px-2 py-1">
        <div class="text-[#5A6C8C] uppercase">Feed</div>
        <div class={`font-black text-xs ${snap().feed_age_ms != null && snap().feed_age_ms < 5000 ? 'text-[#E9EFFA]' : 'text-[#FFB224]'}`}>
          {snap().feed_age_ms == null ? 'no ticks' : `${(snap().feed_age_ms / 1000).toFixed(1)}s`}
        </div>
      </div>
    </div>
  )
}

function Underlyings(props) {
  return (
    <div class="space-y-1 mb-2">
      <For each={props.items}>{(u) => (
        <div class="flex justify-between items-center text-[10px] tabular-nums">
          <span class="text-[#E9EFFA] font-bold w-20">{u.underlying}</span>
          <Show when={u.position} fallback={<span class={`font-bold ${STATE_TONE[u.state] || 'text-[#FFB224]'}`}>{u.state}</span>}>
            <span class="text-[#8CA0BF]">
              {u.position.option_type} ×{u.position.quantity_lots} @ {u.position.entry_price}
              <span class="text-[#FF4D6D]"> SL {u.position.stop_price ?? '--'}</span>
              <span class="text-[#19E3B1]"> TP {u.position.target_price ?? '--'}</span>
            </span>
            <span class={`font-bold ${pnlTone(u.position.unrealized_pnl_inr ?? 0)}`}>{inr(u.position.unrealized_pnl_inr)}</span>
          </Show>
        </div>
      )}</For>
    </div>
  )
}

function Intents(props) {
  return (
    <div>
      <div class="text-[9px] uppercase tracking-wider text-[#5A6C8C] mb-1">Signals sent to agent</div>
      <Show when={props.items.length} fallback={<span class="text-[10px] text-[#5A6C8C]">none yet</span>}>
        <div class="space-y-0.5">
          <For each={props.items}>{(i) => (
            <div class="flex justify-between gap-2 text-[10px] tabular-nums" title={i.detail || ''}>
              <span class="text-[#5A6C8C]">{time(i.issued_at)}</span>
              <span class="text-[#E9EFFA] truncate">{i.underlying} <span class={i.direction === 'BULLISH' ? 'text-[#19E3B1]' : 'text-[#FF4D6D]'}>{i.direction === 'BULLISH' ? 'CE' : 'PE'}</span> <span class="text-[#5A6C8C]">{i.strategy}</span></span>
              <span class={`font-bold ${OUTCOME_TONE[i.outcome] || 'text-[#3FC1FF]'}`}>{i.code || i.outcome}</span>
            </div>
          )}</For>
        </div>
      </Show>
    </div>
  )
}

/** Read-only view of options-trading-agent: heartbeat, kill switch, day P&L, slot states and intent outcomes. */
export default function AgentCard(props) {
  const intents = () => (props.status?.recent_intents || []).slice(0, props.intentLimit || 5)
  return (
    <section class={props.class || 'px-4 py-3 border-b border-[#182742]'}>
      <Show when={props.status} fallback={<span class="text-[11px] text-[#5A6C8C]">connecting to agent status…</span>}>
        <Header status={props.status} />
        <Show when={props.status.snapshot} fallback={<div class="text-[11px] text-[#FF4D6D] mb-2">Agent not publishing a heartbeat{props.status.engine === 'agent' ? ' — forwarded signals will expire unanswered' : ''}.</div>}>
          <Show when={props.status.snapshot.kill_switch.engaged}>
            <div class="text-[10px] font-bold text-[#FF4D6D] mb-2">KILL SWITCH: {props.status.snapshot.kill_switch.reason || 'engaged'}</div>
          </Show>
          <Summary snapshot={props.status.snapshot} />
          <Show when={props.status.snapshot.entry_window}>
            <div class="text-[10px] text-[#5A6C8C] mb-2">Entry window {hhmm(props.status.snapshot.entry_window.start_minute)}–{hhmm(props.status.snapshot.entry_window.end_minute)} IST</div>
          </Show>
          <Underlyings items={props.status.snapshot.underlyings} />
        </Show>
        <Intents items={intents()} />
      </Show>
    </section>
  )
}

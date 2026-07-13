import { createSignal, onMount, For, Show } from 'solid-js'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../ui/Table'
import Badge from '../ui/Badge'
import Button from '../ui/Button'
import Select from '../ui/Select'
import Input from '../ui/Input'

const SYMBOLS = [
  { value: 'NIFTY', label: 'NIFTY' },
  { value: 'BANKNIFTY', label: 'BANKNIFTY' },
  { value: 'SENSEX', label: 'SENSEX' }
]
const DIRECTIONS = [
  { value: 'bullish', label: 'Bullish (CE)' },
  { value: 'bearish', label: 'Bearish (PE)' }
]
const EXPIRY_FLAGS = [
  { value: 'WEEK', label: 'Weekly' },
  { value: 'MONTH', label: 'Monthly' }
]
const ENTRY_MODELS = [
  { value: 'next_candle_open', label: 'Next candle open' },
  { value: 'same_candle_open', label: 'Same candle open' },
  { value: 'signal_candle_close', label: 'Signal candle close' }
]

function statusVariant(status) {
  switch (status) {
    case 'scored': return 'success'
    case 'no_data': return 'outline'
    case 'failed': return 'danger'
    default: return 'outline'
  }
}

function fmtPct(v) {
  if (v === null || v === undefined) return '—'
  return `${v >= 0 ? '+' : ''}${v.toFixed(2)}%`
}

function fmtTime(v) {
  if (!v) return '—'
  return new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false })
}

function nowLocal() {
  const d = new Date()
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export default function SignalPipelinePanel() {
  const [symbol, setSymbol] = createSignal('SENSEX')
  const [timestamp, setTimestamp] = createSignal(nowLocal())
  const [spotPrice, setSpotPrice] = createSignal('')
  const [direction, setDirection] = createSignal('bullish')
  const [expiryFlag, setExpiryFlag] = createSignal('WEEK')
  const [maxDistance, setMaxDistance] = createSignal('2')
  const [entryModel, setEntryModel] = createSignal('next_candle_open')

  const [running, setRunning] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [signal, setSignal] = createSignal(null)
  const [candidates, setCandidates] = createSignal([])

  const [history, setHistory] = createSignal([])
  const [historyLoading, setHistoryLoading] = createSignal(false)

  async function fetchSpotPrice() {
    const ts = timestamp()
    if (!ts) return
    try {
      const res = await fetch(`/api/candles/${symbol()}?interval=1&days=5`)
      const data = await res.json()
      const targetMs = new Date(ts).getTime()
      const closest = (data.candles || []).reduce((best, c) => {
        const diff = Math.abs(c.time * 1000 - targetMs)
        return diff < best.diff ? { candle: c, diff } : best
      }, { candle: null, diff: Infinity }).candle
      if (closest) setSpotPrice(String(closest.close))
    } catch {
      // spot price is a convenience; leave empty on failure
    }
  }

  async function fetchHistory() {
    setHistoryLoading(true)
    try {
      const res = await fetch('/api/research/signals?per_page=10')
      const data = await res.json()
      setHistory(data.signals || [])
    } catch {
      // history is best-effort; leave the list empty on failure
    } finally {
      setHistoryLoading(false)
    }
  }

  onMount(() => {
    fetchHistory()
    fetchSpotPrice()
  })

  async function runPipeline(e) {
    e.preventDefault()
    setError(null)
    setRunning(true)
    try {
      const res = await fetch('/api/research/signals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          underlying_symbol: symbol(),
          signal_timestamp: timestamp(),
          spot_price: spotPrice(),
          direction: direction(),
          expiry_flag: expiryFlag(),
          max_distance: maxDistance(),
          entry_model: entryModel()
        })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setSignal(data.signal)
      setCandidates(data.candidates || [])
      fetchHistory()
    } catch (err) {
      setError(err.message)
    } finally {
      setRunning(false)
    }
  }

  async function loadSignal(id) {
    setError(null)
    try {
      const res = await fetch(`/api/research/signals/${id}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setSignal(data.signal)
      setCandidates(data.candidates || [])
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <div class="flex flex-col gap-6">
      <form onSubmit={runPipeline} class="glass rounded-2xl border border-white/5 px-6 py-5">
        <div class="flex flex-wrap items-end gap-4">
          <div class="w-36">
            <Select label="Symbol" value={symbol()} onChange={(e) => { setSymbol(e.target.value); fetchSpotPrice() }} options={SYMBOLS} />
          </div>
          <div class="w-56">
            <Input label="Signal Timestamp" type="datetime-local" value={timestamp()} onInput={(e) => { setTimestamp(e.target.value); fetchSpotPrice() }} />
          </div>
          <div class="w-32">
            <Input label="Spot Price" type="number" step="0.01" value={spotPrice()} onInput={(e) => setSpotPrice(e.target.value)} />
          </div>
          <div class="w-44">
            <Select label="Direction" value={direction()} onChange={(e) => setDirection(e.target.value)} options={DIRECTIONS} />
          </div>
          <div class="w-32">
            <Select label="Expiry" value={expiryFlag()} onChange={(e) => setExpiryFlag(e.target.value)} options={EXPIRY_FLAGS} />
          </div>
          <div class="w-24">
            <Input label="Max ± Strikes" type="number" min="0" max="10" value={maxDistance()} onInput={(e) => setMaxDistance(e.target.value)} />
          </div>
          <div class="w-56">
            <Select label="Entry Model" value={entryModel()} onChange={(e) => setEntryModel(e.target.value)} options={ENTRY_MODELS} />
          </div>
          <Button type="submit" loading={running()} disabled={!timestamp() || !spotPrice()}>
            Run Pipeline
          </Button>
        </div>
        <Show when={error()}>
          <div class="text-rose-400 text-xs mt-3">⚠ {error()}</div>
        </Show>
      </form>

      <Show when={signal()}>
        <div class="glass rounded-2xl border border-white/5 px-6 py-4">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs font-black text-white uppercase tracking-widest">
              {signal().underlying_symbol} {signal().direction} @ {signal().spot_price} — {fmtTime(signal().signal_timestamp)}
            </h3>
            <Badge variant="outline" class="text-[10px] uppercase">{candidates().length} candidates</Badge>
          </div>
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="bg-white/[0.02]">
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Strike</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Type</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Status</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Entry</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Exit</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">MFE</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">MAE</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Return</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Hold (min)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={candidates()}>
                  {(c) => (
                    <TableRow class="hover:bg-white/[0.03]">
                      <TableCell class="p-3 text-sm font-bold text-white">{c.strike_label}</TableCell>
                      <TableCell class="p-3"><Badge variant={c.option_type === 'CE' ? 'success' : 'danger'} class="text-[10px]">{c.option_type}</Badge></TableCell>
                      <TableCell class="p-3"><Badge variant={statusVariant(c.status)} class="text-[10px] uppercase">{c.status}</Badge></TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{c.entry_price ?? '—'}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{c.exit_price ?? '—'}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-emerald-400">{fmtPct(c.mfe_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-rose-400">{fmtPct(c.mae_pct)}</TableCell>
                      <TableCell class={`p-3 text-right text-xs font-bold ${c.return_pct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{fmtPct(c.return_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-400">{c.holding_minutes ?? '—'}</TableCell>
                    </TableRow>
                  )}
                </For>
                <Show when={candidates().length === 0}>
                  <TableRow><TableCell colspan="9" class="p-8 text-center text-gray-600 text-xs uppercase">No candidates (direction may resolve to no_trade)</TableCell></TableRow>
                </Show>
              </TableBody>
            </Table>
          </div>
        </div>
      </Show>

      <div class="glass rounded-2xl border border-white/5 px-6 py-4">
        <h3 class="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Recent Signals</h3>
        <Show when={historyLoading()}>
          <div class="text-xs text-gray-600 uppercase">Loading...</div>
        </Show>
        <div class="flex flex-col divide-y divide-white/5">
          <For each={history()}>
            {(s) => (
              <button
                onClick={() => loadSignal(s.id)}
                class="flex items-center justify-between py-2.5 text-left hover:bg-white/[0.03] px-2 rounded transition-colors"
              >
                <span class="text-xs font-bold text-gray-300">{s.underlying_symbol} · {s.direction} · {fmtTime(s.signal_timestamp)}</span>
                <span class="text-[10px] text-gray-600 uppercase">{s.candidate_count} candidates</span>
              </button>
            )}
          </For>
          <Show when={history().length === 0 && !historyLoading()}>
            <div class="py-6 text-center text-gray-600 text-xs uppercase">No signals yet — run the pipeline above</div>
          </Show>
        </div>
      </div>
    </div>
  )
}
